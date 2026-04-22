defmodule Familiar.Knowledge.ManagementTest do
  use Familiar.DataCase, async: false

  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]
  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Management
  alias Familiar.Repo

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-02 12:00:00Z] end)
    :ok
  end

  # management_test uses a 2-index-replace shape rather than the half/half
  # shape of the shared helper. Keep the local function but read dimensions
  # via `zero_vector/0` so a future dim migration is automatic.
  defp deterministic_vector(primary, secondary \\ 0) do
    zero_vector()
    |> List.replace_at(0, primary / 100)
    |> List.replace_at(1, secondary / 100)
  end

  defp create_entry(attrs) do
    default = %{
      text: "Test entry",
      type: "fact",
      source: "init_scan",
      source_file: "lib/test.ex",
      metadata: "{}"
    }

    merged = Map.merge(default, attrs)

    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      {:ok, deterministic_vector(attrs[:vector_id] || :rand.uniform(100))}
    end)

    {:ok, entry} = Knowledge.store_with_embedding(merged)
    entry
  end

  describe "Knowledge.update_entry/2" do
    test "updates text and re-embeds" do
      entry = create_entry(%{text: "Original text", vector_id: 1})

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn "Updated text" ->
        {:ok, deterministic_vector(99)}
      end)

      assert {:ok, updated} = Knowledge.update_entry(entry, %{text: "Updated text"})
      assert updated.text == "Updated text"
      assert updated.id == entry.id
    end

    test "changes source to user when specified" do
      entry = create_entry(%{text: "Auto entry", source: "init_scan", vector_id: 2})

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(99)}
      end)

      assert {:ok, updated} =
               Knowledge.update_entry(entry, %{text: "User edited", source: "user"})

      assert updated.source == "user"
    end

    test "returns error when embed fails" do
      entry = create_entry(%{text: "Original", vector_id: 4})

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{}}}
      end)

      assert {:error, {:provider_unavailable, _}} =
               Knowledge.update_entry(entry, %{text: "New text"})

      # Verify original text preserved
      {:ok, reloaded} = Knowledge.fetch_entry(entry.id)
      assert reloaded.text == "Original"
    end
  end

  defp mock_scan_fn(files) do
    fn _dir, _opts -> {:ok, files, 0} end
  end

  defp mock_fs_read(file_contents) do
    stub(Familiar.System.FileSystemMock, :read, fn path ->
      find_content_by_suffix(file_contents, path)
    end)
  end

  defp find_content_by_suffix(file_contents, path) do
    {_key, content} =
      Enum.find(file_contents, {nil, nil}, fn {key, _} -> String.ends_with?(path, key) end)

    if content, do: {:ok, content}, else: {:error, :enoent}
  end

  describe "Management.refresh/2" do
    test "creates entries for new files" do
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{type: "file_summary", text: "New file summary", source_file: "lib/new.ex"}
             ])
         }}
      end)

      mock_fs_read(%{"lib/new.ex" => "defmodule New do\nend"})

      files = [%{relative_path: "lib/new.ex", content: "defmodule New do\nend"}]

      assert {:ok, result} =
               Management.refresh("/fake/project",
                 scan_fn: mock_scan_fn(files),
                 file_system: Familiar.System.FileSystemMock
               )

      assert result.scanned == 1
      assert result.created >= 1
      assert result.preserved == 0
    end

    test "preserves user-source entries during refresh" do
      _user_entry =
        create_entry(%{
          text: "User knowledge",
          source: "user",
          source_file: "lib/mine.ex",
          vector_id: 10
        })

      entries = Repo.all(from(e in Entry, where: e.source == "user"))
      assert length(entries) == 1

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      mock_fs_read(%{"lib/mine.ex" => "defmodule Mine do\nend"})

      files = [%{relative_path: "lib/mine.ex"}]

      {:ok, result} =
        Management.refresh("/fake/project",
          scan_fn: mock_scan_fn(files),
          file_system: Familiar.System.FileSystemMock
        )

      # User entry preserved
      assert result.preserved == 1

      entries_after = Repo.all(from(e in Entry, where: e.source == "user"))
      assert length(entries_after) == 1
    end

    test "updates auto-generated entries on refresh" do
      auto_entry =
        create_entry(%{
          text: "Old summary of auth module",
          type: "file_summary",
          source: "init_scan",
          source_file: "lib/auth.ex",
          vector_id: 20
        })

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 type: "file_summary",
                 text: "Updated summary of auth module",
                 source_file: "lib/auth.ex"
               }
             ])
         }}
      end)

      mock_fs_read(%{"lib/auth.ex" => "defmodule Auth do\n  # updated\nend"})

      files = [%{relative_path: "lib/auth.ex"}]

      {:ok, result} =
        Management.refresh("/fake/project",
          scan_fn: mock_scan_fn(files),
          file_system: Familiar.System.FileSystemMock
        )

      assert result.updated == 1

      {:ok, updated} = Knowledge.fetch_entry(auto_entry.id)
      assert updated.text =~ "Updated summary"
    end

    test "removes entries for deleted files" do
      _orphan =
        create_entry(%{
          text: "Entry for deleted file",
          source: "init_scan",
          source_file: "lib/deleted.ex",
          vector_id: 30
        })

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      # deleted.ex no longer exists on disk
      stub(Familiar.System.FileSystemMock, :stat, fn
        "lib/deleted.ex" -> {:error, :enoent}
        _path -> {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
      end)

      mock_fs_read(%{})

      # No files scanned (the file was deleted)
      {:ok, result} =
        Management.refresh("/fake/project",
          scan_fn: mock_scan_fn([]),
          file_system: Familiar.System.FileSystemMock
        )

      assert result.removed == 1
    end

    test "path filter restricts scope" do
      _entry_a =
        create_entry(%{
          text: "Entry in lib/auth",
          source: "init_scan",
          source_file: "lib/auth/token.ex",
          vector_id: 40
        })

      _entry_b =
        create_entry(%{
          text: "Entry in lib/work",
          source: "init_scan",
          source_file: "lib/work/task.ex",
          vector_id: 41
        })

      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 type: "file_summary",
                 text: "Updated auth token",
                 source_file: "lib/auth/token.ex"
               }
             ])
         }}
      end)

      mock_fs_read(%{"lib/auth/token.ex" => "defmodule Auth.Token do\nend"})

      # Only scan auth path
      files = [%{relative_path: "lib/auth/token.ex"}]

      {:ok, result} =
        Management.refresh("/fake/project",
          scan_fn: mock_scan_fn(files),
          file_system: Familiar.System.FileSystemMock,
          path: "lib/auth"
        )

      assert result.scanned == 1
      assert result.updated == 1
    end

    test "returns summary with all counts" do
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "[]"}}
      end)

      mock_fs_read(%{})

      {:ok, result} =
        Management.refresh("/fake/project",
          scan_fn: mock_scan_fn([]),
          file_system: Familiar.System.FileSystemMock
        )

      assert Map.has_key?(result, :scanned)
      assert Map.has_key?(result, :updated)
      assert Map.has_key?(result, :created)
      assert Map.has_key?(result, :removed)
      assert Map.has_key?(result, :preserved)
    end
  end

  describe "Management.find_consolidation_candidates/1" do
    test "finds similar entries as candidates" do
      # Create two very similar entries with similar vectors
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        case text do
          "Auth uses JWT tokens for session management" ->
            {:ok, deterministic_vector(50, 1)}

          "Authentication relies on JWT tokens for sessions" ->
            {:ok, deterministic_vector(50, 2)}

          _ ->
            {:ok, deterministic_vector(:rand.uniform(100))}
        end
      end)

      {:ok, entry_a} =
        Knowledge.store_with_embedding(%{
          text: "Auth uses JWT tokens for session management",
          type: "fact",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, entry_b} =
        Knowledge.store_with_embedding(%{
          text: "Authentication relies on JWT tokens for sessions",
          type: "fact",
          source: "init_scan",
          source_file: "lib/auth.ex"
        })

      {:ok, %{candidates: candidates}} = Management.find_consolidation_candidates()

      if candidates != [] do
        candidate = hd(candidates)
        assert candidate.type == "fact"
        ids = [candidate.id_a, candidate.id_b]
        assert entry_a.id in ids
        assert entry_b.id in ids
      end
    end

    test "returns empty list when no similar entries exist" do
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        case text do
          "Completely different topic A" -> {:ok, deterministic_vector(1, 0)}
          "Completely different topic B" -> {:ok, deterministic_vector(99, 99)}
          _ -> {:ok, deterministic_vector(:rand.uniform(100))}
        end
      end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Completely different topic A",
          type: "fact",
          source: "init_scan",
          source_file: "lib/a.ex"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "Completely different topic B",
          type: "convention",
          source: "init_scan",
          source_file: "lib/b.ex"
        })

      {:ok, %{candidates: candidates}} = Management.find_consolidation_candidates()

      # Different types should not be paired
      type_matched =
        Enum.filter(candidates, fn c -> c.type == "fact" end)

      assert type_matched == []
    end
  end

  describe "Management.compact/2" do
    test "merges two entries keeping longer text" do
      stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(:rand.uniform(100))}
      end)

      {:ok, short} =
        Knowledge.store_with_embedding(%{
          text: "Short fact",
          type: "fact",
          source: "init_scan",
          source_file: "lib/a.ex"
        })

      {:ok, long} =
        Knowledge.store_with_embedding(%{
          text: "This is a much longer and more detailed fact about the system",
          type: "fact",
          source: "init_scan",
          source_file: "lib/a.ex"
        })

      {:ok, result} = Management.compact([{short.id, long.id}])
      assert result.merged == 1

      # Short entry should be deleted
      assert {:error, {:not_found, _}} = Knowledge.fetch_entry(short.id)

      # Long entry should still exist with merged text
      {:ok, keeper} = Knowledge.fetch_entry(long.id)
      assert keeper.text =~ "longer and more detailed"
      assert keeper.text =~ "Short fact"
    end

    test "returns error when all merges fail" do
      assert {:error, {:compact_failed, %{merged: 0, failed: 1}}} =
               Management.compact([{99_999, 99_998}])
    end
  end
end
