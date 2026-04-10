defmodule Familiar.Knowledge.EmbeddingPipelineTest do
  use Familiar.DataCase, async: false

  import Familiar.Test.EmbeddingHelpers
  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbedderMock

  # Must be async: false because sqlite-vec virtual tables
  # don't participate in Ecto sandbox transactions.

  setup :verify_on_exit!

  setup do
    # Clean up the virtual table between tests (not sandboxed)
    Familiar.Repo.query!("DELETE FROM knowledge_entry_embeddings")
    :ok
  end

  describe "store_with_embedding/1" do
    test "stores entry and embedding, makes it retrievable" do
      vector = deterministic_vector(1.0, 0.0)

      expect(EmbedderMock, :embed, fn text ->
        assert text == "Handler files follow snake_case naming"
        {:ok, vector}
      end)

      assert {:ok, entry} =
               Knowledge.store_with_embedding(%{
                 text: "Handler files follow snake_case naming",
                 type: "convention",
                 source: "init_scan",
                 source_file: "handler/song.go"
               })

      assert entry.id
      assert entry.text == "Handler files follow snake_case naming"
      assert entry.type == "convention"
      assert entry.source == "init_scan"

      # Verify embedding was stored in virtual table
      {:ok, %{rows: rows}} =
        Familiar.Repo.query(
          "SELECT entry_id FROM knowledge_entry_embeddings WHERE entry_id = ?",
          [entry.id]
        )

      assert length(rows) == 1
    end

    test "returns validation error for missing required fields" do
      assert {:error, {:validation_failed, %{changeset: changeset}}} =
               Knowledge.store_with_embedding(%{text: "some text"})

      refute changeset.valid?
    end

    test "returns validation error for invalid type" do
      assert {:error, {:validation_failed, %{changeset: changeset}}} =
               Knowledge.store_with_embedding(%{
                 text: "some text",
                 type: "invalid_type",
                 source: "init_scan"
               })

      refute changeset.valid?
    end

    test "returns provider error when embedding fails" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}
      end)

      assert {:error, {:provider_unavailable, _}} =
               Knowledge.store_with_embedding(%{
                 text: "some text",
                 type: "convention",
                 source: "init_scan"
               })
    end
  end

  describe "search_similar/2" do
    test "returns entries ranked by distance to query" do
      v_close = deterministic_vector(1.0, 0.0)
      v_medium = deterministic_vector(0.7, 0.3)
      v_far = deterministic_vector(0.0, 1.0)

      # Mock embed for 3 store calls + 1 search query call
      EmbedderMock
      |> expect(:embed, fn "close to query" -> {:ok, v_close} end)
      |> expect(:embed, fn "medium distance" -> {:ok, v_medium} end)
      |> expect(:embed, fn "far from query" -> {:ok, v_far} end)
      |> expect(:embed, fn "search query" -> {:ok, v_close} end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "close to query",
          type: "convention",
          source: "init_scan"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "medium distance",
          type: "convention",
          source: "init_scan"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "far from query",
          type: "convention",
          source: "init_scan"
        })

      assert {:ok, results} = Knowledge.search_similar("search query")

      assert length(results) == 3
      [first, second, third] = results
      assert first.distance <= second.distance
      assert second.distance <= third.distance
      assert first.entry.text == "close to query"
      assert third.entry.text == "far from query"
    end

    test "respects limit option" do
      v = deterministic_vector(0.5, 0.5)

      EmbedderMock
      |> expect(:embed, fn _ -> {:ok, v} end)
      |> expect(:embed, fn _ -> {:ok, v} end)
      |> expect(:embed, fn "query" -> {:ok, v} end)

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "entry 1",
          type: "convention",
          source: "init_scan"
        })

      {:ok, _} =
        Knowledge.store_with_embedding(%{
          text: "entry 2",
          type: "convention",
          source: "init_scan"
        })

      assert {:ok, results} = Knowledge.search_similar("query", limit: 1)
      assert length(results) == 1
    end

    test "returns empty list when no entries exist" do
      v = deterministic_vector(0.5, 0.5)

      expect(EmbedderMock, :embed, fn "query" -> {:ok, v} end)

      assert {:ok, []} = Knowledge.search_similar("query")
    end

    test "returns error when embedding fails" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}
      end)

      assert {:error, {:provider_unavailable, _}} = Knowledge.search_similar("query")
    end
  end
end
