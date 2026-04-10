defmodule Familiar.Knowledge.EmbeddingMetadataTest do
  use Familiar.DataCase, async: false

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbeddingMetadata
  alias Familiar.Knowledge.EmbeddingMetadataRow
  alias Familiar.Repo

  setup do
    # Reset the singleton row between tests so drift logic starts clean.
    Repo.update_all(EmbeddingMetadataRow, set: [model_name: nil, dimensions: nil])
    Repo.delete_all(Familiar.Knowledge.Entry)
    Repo.query!("DELETE FROM knowledge_entry_embeddings")
    :ok
  end

  describe "get/0" do
    test "returns the seeded singleton row with nil fields on a fresh database" do
      assert {:ok, %{model_name: nil, dimensions: nil}} = EmbeddingMetadata.get()
    end

    test "lazy-creates the row if the migration-seeded row is missing" do
      Repo.delete_all(EmbeddingMetadataRow)
      assert {:ok, %{model_name: nil, dimensions: nil}} = EmbeddingMetadata.get()
      assert Repo.aggregate(EmbeddingMetadataRow, :count, :id) == 1
    end
  end

  describe "set/2" do
    test "upserts the singleton row with the given model + dimensions" do
      assert {:ok, %{model_name: "text-embedding-3-small", dimensions: 1536}} =
               EmbeddingMetadata.set("text-embedding-3-small", 1536)

      assert {:ok, %{model_name: "text-embedding-3-small", dimensions: 1536}} =
               EmbeddingMetadata.get()
    end

    test "updates in place (no duplicate rows)" do
      {:ok, _} = EmbeddingMetadata.set("nomic-embed-text", 768)
      {:ok, _} = EmbeddingMetadata.set("text-embedding-3-small", 1536)

      assert Repo.aggregate(EmbeddingMetadataRow, :count, :id) == 1
      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end

    test "rejects non-positive dimensions via the changeset" do
      assert {:error, {:embedding_metadata_update_failed, _}} =
               EmbeddingMetadata.set("anything", 0)
    end
  end

  describe "current_model/0" do
    test "returns nil when unset" do
      assert EmbeddingMetadata.current_model() == nil
    end

    test "returns the stored model once set" do
      {:ok, _} = EmbeddingMetadata.set("text-embedding-3-small", 1536)
      assert EmbeddingMetadata.current_model() == "text-embedding-3-small"
    end
  end

  describe "check_drift/1" do
    test "returns :ok when configured is nil (no drift check)" do
      assert EmbeddingMetadata.check_drift(nil) == :ok
    end

    test "returns :ok when stored matches configured" do
      {:ok, _} = EmbeddingMetadata.set("text-embedding-3-small", 1536)
      assert EmbeddingMetadata.check_drift("text-embedding-3-small") == :ok
    end

    test "returns :ok on clean install (stored nil, zero entries)" do
      assert EmbeddingMetadata.check_drift("text-embedding-3-small") == :ok
    end

    test "returns :model_unset when stored is nil but entries exist" do
      {:ok, _} =
        Repo.insert(%Familiar.Knowledge.Entry{
          text: "an entry",
          type: "fact",
          source: "manual"
        })

      assert {:warning, :model_unset, %{stored: nil, configured: "text-embedding-3-small"}} =
               EmbeddingMetadata.check_drift("text-embedding-3-small")
    end

    test "returns :model_changed when stored differs from configured" do
      {:ok, _} = EmbeddingMetadata.set("nomic-embed-text", 768)

      assert {:warning, :model_changed,
              %{stored: "nomic-embed-text", configured: "text-embedding-3-small"}} =
               EmbeddingMetadata.check_drift("text-embedding-3-small")
    end
  end

  describe "interaction with Knowledge.embedding_dimensions/0" do
    test "persists dimensions matching the configured value" do
      {:ok, _} =
        EmbeddingMetadata.set("text-embedding-3-small", Knowledge.embedding_dimensions())

      {:ok, stored} = EmbeddingMetadata.get()
      assert stored.dimensions == Knowledge.embedding_dimensions()
    end
  end
end
