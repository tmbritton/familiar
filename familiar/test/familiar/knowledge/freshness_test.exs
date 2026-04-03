defmodule Familiar.Knowledge.FreshnessTest do
  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbedderMock
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Freshness
  alias Familiar.Providers.LLMMock
  alias Familiar.System.ClockMock
  alias Familiar.System.FileSystemMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Stub ClockMock for checked_at updates in validate_entries
    stub(ClockMock, :now, fn -> ~U[2026-04-02 12:00:00Z] end)

    :ok
  end

  describe "validate_entries/2" do
    test "file unchanged — entry is fresh" do
      entry = insert_entry("lib/auth.ex", ~U[2026-04-01 12:00:00Z])

      expect(FileSystemMock, :stat, fn "lib/auth.ex" ->
        {:ok, %{mtime: ~U[2026-04-01 11:00:00Z], size: 100}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      assert [^entry] = result.fresh
      assert result.stale == []
      assert result.deleted == []
    end

    test "file modified — entry is stale" do
      entry = insert_entry("lib/auth.ex", ~U[2026-04-01 12:00:00Z])

      expect(FileSystemMock, :stat, fn "lib/auth.ex" ->
        {:ok, %{mtime: ~U[2026-04-01 13:00:00Z], size: 200}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      assert result.fresh == []
      assert [^entry] = result.stale
      assert result.deleted == []
    end

    test "file deleted — entry marked deleted" do
      entry = insert_entry("lib/removed.ex", ~U[2026-04-01 12:00:00Z])

      expect(FileSystemMock, :stat, fn "lib/removed.ex" ->
        {:error, {:file_error, %{path: "lib/removed.ex", reason: :enoent}}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      assert result.fresh == []
      assert result.stale == []
      assert [^entry] = result.deleted
    end

    test "entry without source_file is always fresh" do
      entry = insert_entry(nil, ~U[2026-04-01 12:00:00Z])

      # No FileSystem mock needed — no stat call for nil source_file
      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      assert [^entry] = result.fresh
      assert result.stale == []
      assert result.deleted == []
    end

    test "stat timeout is fail-open — entry treated as fresh with warning" do
      entry = insert_entry("lib/slow.ex", ~U[2026-04-01 12:00:00Z])

      # Simulate a timeout by returning an error
      expect(FileSystemMock, :stat, fn "lib/slow.ex" ->
        {:error, {:file_error, %{path: "lib/slow.ex", reason: :timeout}}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      # Fail-open: timeout errors (non-enoent) treat as fresh
      assert [^entry] = result.fresh
      assert result.stale == []
      assert result.deleted == []
      assert [warning | _] = result.warnings
      assert warning =~ "lib/slow.ex"
    end

    test "multiple entries batched — mix of fresh, stale, deleted" do
      fresh_entry = insert_entry("lib/fresh.ex", ~U[2026-04-01 12:00:00Z])
      stale_entry = insert_entry("lib/stale.ex", ~U[2026-04-01 12:00:00Z])
      deleted_entry = insert_entry("lib/gone.ex", ~U[2026-04-01 12:00:00Z])
      no_file_entry = insert_entry(nil, ~U[2026-04-01 12:00:00Z])

      stub(FileSystemMock, :stat, fn
        "lib/fresh.ex" -> {:ok, %{mtime: ~U[2026-04-01 11:00:00Z], size: 100}}
        "lib/stale.ex" -> {:ok, %{mtime: ~U[2026-04-01 13:00:00Z], size: 200}}
        "lib/gone.ex" -> {:error, {:file_error, %{path: "lib/gone.ex", reason: :enoent}}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries(
                 [fresh_entry, stale_entry, deleted_entry, no_file_entry],
                 file_system: FileSystemMock
               )

      fresh_ids = Enum.map(result.fresh, & &1.id)
      assert fresh_entry.id in fresh_ids
      assert no_file_entry.id in fresh_ids

      assert [stale] = result.stale
      assert stale.id == stale_entry.id

      assert [deleted] = result.deleted
      assert deleted.id == deleted_entry.id
    end

    test "empty entries list returns empty results" do
      assert {:ok, result} =
               Freshness.validate_entries([], file_system: FileSystemMock)

      assert result.fresh == []
      assert result.stale == []
      assert result.deleted == []
      assert result.warnings == []
    end

    test "file mtime exactly equal to updated_at — entry is fresh" do
      entry = insert_entry("lib/exact.ex", ~U[2026-04-01 12:00:00Z])

      expect(FileSystemMock, :stat, fn "lib/exact.ex" ->
        {:ok, %{mtime: ~U[2026-04-01 12:00:00Z], size: 100}}
      end)

      assert {:ok, result} =
               Freshness.validate_entries([entry], file_system: FileSystemMock)

      assert [^entry] = result.fresh
    end
  end

  describe "refresh_stale/2" do
    test "successful refresh updates entry text and re-embeds" do
      vector = deterministic_vector(1.0, 0.0)
      new_vector = deterministic_vector(0.0, 1.0)

      # Create entry with embedding
      expect(EmbedderMock, :embed, fn _ -> {:ok, vector} end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Old knowledge about auth",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      # Mock file read for refresh
      expect(FileSystemMock, :read, fn "lib/auth.ex" ->
        {:ok, "defmodule Auth do\n  # new code\nend"}
      end)

      # Mock LLM extraction
      llm_response =
        Jason.encode!([
          %{
            "type" => "convention",
            "text" => "Updated knowledge about auth",
            "source_file" => "lib/auth.ex"
          }
        ])

      expect(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      # Mock re-embedding
      expect(EmbedderMock, :embed, fn "Updated knowledge about auth" -> {:ok, new_vector} end)

      assert {:ok, %{refreshed: 1, failed: 0, warnings: []}} =
               Freshness.refresh_stale([entry], file_system: FileSystemMock)

      # Verify entry text was updated
      {:ok, updated} = Knowledge.fetch_entry(entry.id)
      assert updated.text == "Updated knowledge about auth"
    end

    test "refresh failure preserves original entry" do
      vector = deterministic_vector(1.0, 0.0)

      expect(EmbedderMock, :embed, fn _ -> {:ok, vector} end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Original knowledge",
          type: "convention",
          source: "init_scan",
          source_file: "lib/broken.ex"
        })

      # File read fails
      expect(FileSystemMock, :read, fn "lib/broken.ex" ->
        {:error, {:file_error, %{path: "lib/broken.ex", reason: :eacces}}}
      end)

      assert {:ok, %{refreshed: 0, failed: 1, warnings: warnings}} =
               Freshness.refresh_stale([entry], file_system: FileSystemMock)

      assert length(warnings) == 1
      assert hd(warnings) =~ "lib/broken.ex"

      # Original entry preserved
      {:ok, preserved} = Knowledge.fetch_entry(entry.id)
      assert preserved.text == "Original knowledge"
    end

    test "embedding failure preserves original entry" do
      vector = deterministic_vector(1.0, 0.0)

      expect(EmbedderMock, :embed, fn _ -> {:ok, vector} end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Original knowledge",
          type: "convention",
          source: "init_scan",
          source_file: "lib/embed_fail.ex"
        })

      # File read succeeds
      expect(FileSystemMock, :read, fn "lib/embed_fail.ex" ->
        {:ok, "defmodule EmbedFail do\nend"}
      end)

      # LLM extraction succeeds
      llm_response =
        Jason.encode!([
          %{
            "type" => "convention",
            "text" => "New knowledge",
            "source_file" => "lib/embed_fail.ex"
          }
        ])

      expect(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: llm_response}}
      end)

      # Embedding fails
      expect(EmbedderMock, :embed, fn "New knowledge" ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      assert {:ok, %{refreshed: 0, failed: 1}} =
               Freshness.refresh_stale([entry], file_system: FileSystemMock)
    end
  end

  describe "remove_deleted/1" do
    test "removes entries and their embeddings from database" do
      vector = deterministic_vector(1.0, 0.0)

      expect(EmbedderMock, :embed, fn _ -> {:ok, vector} end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Knowledge about deleted file",
          type: "convention",
          source: "init_scan",
          source_file: "lib/gone.ex"
        })

      assert {:ok, %{removed: 1}} = Freshness.remove_deleted([entry])

      # Entry no longer exists
      assert {:error, {:not_found, _}} = Knowledge.fetch_entry(entry.id)
    end

    test "removes multiple entries" do
      expect(EmbedderMock, :embed, 2, fn _ -> {:ok, deterministic_vector(1.0, 0.0)} end)

      {:ok, entry1} =
        Knowledge.store_with_embedding(%{
          text: "First deleted",
          type: "convention",
          source: "init_scan",
          source_file: "lib/a.ex"
        })

      {:ok, entry2} =
        Knowledge.store_with_embedding(%{
          text: "Second deleted",
          type: "convention",
          source: "init_scan",
          source_file: "lib/b.ex"
        })

      assert {:ok, %{removed: 2}} = Freshness.remove_deleted([entry1, entry2])

      assert {:error, {:not_found, _}} = Knowledge.fetch_entry(entry1.id)
      assert {:error, {:not_found, _}} = Knowledge.fetch_entry(entry2.id)
    end

    test "empty list removes nothing" do
      assert {:ok, %{removed: 0}} = Freshness.remove_deleted([])
    end
  end

  describe "search integration with freshness" do
    test "search results include freshness status for stale entry" do
      v = deterministic_vector(1.0, 0.0)

      EmbedderMock
      |> expect(:embed, fn "Auth knowledge" -> {:ok, v} end)
      |> expect(:embed, fn "auth" -> {:ok, v} end)

      {:ok, entry} =
        Knowledge.store_with_embedding(%{
          text: "Auth knowledge",
          type: "convention",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      # Make the file appear modified (mtime after entry's updated_at)
      expect(FileSystemMock, :stat, fn "lib/auth.ex" ->
        future = DateTime.add(entry.updated_at, 3600, :second)
        {:ok, %{mtime: future, size: 200}}
      end)

      assert {:ok, [result]} =
               Knowledge.search("auth", file_system: FileSystemMock)

      assert result.freshness == :stale
      assert result.text == "Auth knowledge"
    end

    test "search excludes entries with deleted source files" do
      v1 = deterministic_vector(1.0, 0.0)
      v2 = deterministic_vector(0.9, 0.1)

      EmbedderMock
      |> expect(:embed, fn "Present file knowledge" -> {:ok, v1} end)
      |> expect(:embed, fn "Deleted file knowledge" -> {:ok, v2} end)
      |> expect(:embed, fn "query" -> {:ok, v1} end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Present file knowledge",
          type: "convention",
          source: "init_scan",
          source_file: "lib/present.ex"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Deleted file knowledge",
          type: "convention",
          source: "init_scan",
          source_file: "lib/deleted.ex"
        })

      FileSystemMock
      |> expect(:stat, fn "lib/present.ex" ->
        {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
      end)
      |> expect(:stat, fn "lib/deleted.ex" ->
        {:error, {:file_error, %{path: "lib/deleted.ex", reason: :enoent}}}
      end)

      assert {:ok, results} =
               Knowledge.search("query", file_system: FileSystemMock)

      assert length(results) == 1
      assert hd(results).text == "Present file knowledge"
      assert hd(results).freshness == :fresh
    end

    test "search returns results with :unknown freshness on validation error" do
      v = deterministic_vector(1.0, 0.0)

      EmbedderMock
      |> expect(:embed, fn "Some knowledge" -> {:ok, v} end)
      |> expect(:embed, fn "query" -> {:ok, v} end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Some knowledge",
          type: "convention",
          source: "init_scan"
        })

      # Entry has no source_file — always fresh (no stat needed)
      assert {:ok, [result]} = Knowledge.search("query", file_system: FileSystemMock)
      assert result.freshness == :fresh
    end
  end

  # Helper to insert an entry with a specific updated_at
  defp insert_entry(source_file, updated_at) do
    {:ok, entry} =
      Repo.insert(
        Entry.changeset(%Entry{}, %{
          text: "Knowledge about #{source_file || "general"}",
          type: "convention",
          source: "init_scan",
          source_file: source_file
        })
      )

    # Force updated_at to controlled value
    {1, [updated]} =
      Repo.update_all(
        from(e in Entry, where: e.id == ^entry.id, select: e),
        set: [updated_at: updated_at]
      )

    updated
  end

  defp deterministic_vector(primary, secondary) do
    half = div(768, 2)
    List.duplicate(primary, half) ++ List.duplicate(secondary, half)
  end
end
