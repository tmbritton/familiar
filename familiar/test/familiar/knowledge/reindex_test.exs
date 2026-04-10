defmodule Familiar.Knowledge.ReindexTest do
  @moduledoc """
  Story 7.5-7 — `Knowledge.reindex_embeddings/1` walks every entry,
  re-embeds via the configured provider (or an injected embedder), and
  replaces stored vectors. Metadata is updated on success.
  """

  use Familiar.DataCase, async: false

  import Familiar.Test.EmbeddingHelpers

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbeddingMetadata
  alias Familiar.Knowledge.EmbeddingMetadataRow
  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  setup do
    Repo.update_all(EmbeddingMetadataRow, set: [model_name: nil, dimensions: nil])
    Repo.delete_all(Entry)
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Make the drift check's current_embedding_model/0 deterministic so
    # reindex has something to record in metadata.
    prev_app = Application.get_env(:familiar, :openai_compatible, [])

    Application.put_env(
      :familiar,
      :openai_compatible,
      Keyword.put(prev_app, :embedding_model, "text-embedding-3-small")
    )

    on_exit(fn ->
      Application.put_env(:familiar, :openai_compatible, prev_app)
    end)

    :ok
  end

  defp seed_entry(text, vector) do
    {:ok, entry} =
      Repo.insert(%Entry{
        text: text,
        type: "fact",
        source: "manual"
      })

    :ok = Knowledge.replace_embedding(entry.id, vector)
    entry
  end

  describe "reindex_embeddings/1 — happy path" do
    test "re-embeds every entry and updates metadata" do
      seed_entry("A", deterministic_vector(1.0, 0.0))
      seed_entry("B", deterministic_vector(0.5, 0.5))
      seed_entry("C", deterministic_vector(0.0, 1.0))

      new_vector_for = fn
        "A" -> deterministic_vector(0.9, 0.1)
        "B" -> deterministic_vector(0.6, 0.4)
        "C" -> deterministic_vector(0.1, 0.9)
      end

      embedder = fn text -> {:ok, new_vector_for.(text)} end

      assert {:ok, %{processed: 3, failed: 0, errors: [], model: model, dimensions: dims}} =
               Knowledge.reindex_embeddings(embedder: embedder)

      assert model == "text-embedding-3-small"
      assert dims == Knowledge.embedding_dimensions()

      # Metadata reflects the new model
      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end

    test "fires :on_progress after each entry" do
      seed_entry("X", deterministic_vector(1.0, 0.0))
      seed_entry("Y", deterministic_vector(0.0, 1.0))

      parent = self()

      on_progress = fn processed, total ->
        send(parent, {:progress, processed, total})
      end

      embedder = fn _ -> {:ok, deterministic_vector(0.5, 0.5)} end

      {:ok, %{processed: 2, failed: 0}} =
        Knowledge.reindex_embeddings(embedder: embedder, on_progress: on_progress)

      assert_received {:progress, 1, 2}
      assert_received {:progress, 2, 2}
    end

    test "works on an empty store and still records the model" do
      embedder = fn _ -> flunk("should not be called") end

      assert {:ok, %{processed: 0, failed: 0, errors: []}} =
               Knowledge.reindex_embeddings(embedder: embedder)

      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end
  end

  describe "store_with_embedding auto-record (AC4)" do
    setup do
      # Stub the embedder mock so store_with_embedding succeeds end-to-end.
      # Mox.set_mox_global is available via MockCase in other tests; here we
      # rely on the `:openai_compatible` embedding_model being set in this
      # file's outer setup so `current_embedding_model/0` returns a string.
      Mox.set_mox_global()

      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
        {:ok, deterministic_vector(1.0, 0.0)}
      end)

      :ok
    end

    test "first store on a fresh install records the configured model in metadata" do
      assert EmbeddingMetadata.current_model() == nil

      assert {:ok, _entry} =
               Knowledge.store_with_embedding(%{
                 text: "First entry",
                 type: "fact",
                 source: "manual"
               })

      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end

    test "subsequent stores do not overwrite an already-set model" do
      {:ok, _} = EmbeddingMetadata.set("manual-override-model", 1536)

      assert {:ok, _entry} =
               Knowledge.store_with_embedding(%{
                 text: "Another entry",
                 type: "fact",
                 source: "manual"
               })

      assert EmbeddingMetadata.current_model() == "manual-override-model"
    end
  end

  describe "reindex_embeddings/1 — fail-soft per entry" do
    test "one failing entry does not abort the others and metadata still updates" do
      a = seed_entry("A", deterministic_vector(1.0, 0.0))
      _b = seed_entry("B", deterministic_vector(0.0, 1.0))

      # a fails, b succeeds
      embedder = fn
        "A" -> {:error, {:provider_unavailable, %{reason: :rate_limited}}}
        "B" -> {:ok, deterministic_vector(0.7, 0.3)}
      end

      assert {:ok, %{processed: 1, failed: 1, errors: [{failing_id, reason}]}} =
               Knowledge.reindex_embeddings(embedder: embedder)

      assert failing_id == a.id
      assert match?({:provider_unavailable, _}, reason)

      # Metadata still updated because at least one entry succeeded
      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end

    test "all entries failing leaves metadata unchanged" do
      _a = seed_entry("A", deterministic_vector(1.0, 0.0))
      _b = seed_entry("B", deterministic_vector(0.0, 1.0))

      embedder = fn _ -> {:error, {:provider_unavailable, %{reason: :timeout}}} end

      assert {:ok, %{processed: 0, failed: 2}} =
               Knowledge.reindex_embeddings(embedder: embedder)

      # Metadata was not updated (no successes)
      assert EmbeddingMetadata.current_model() == nil
    end
  end
end
