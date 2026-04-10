defmodule Familiar.Knowledge.EmbeddingMetadataRow do
  @moduledoc """
  Ecto schema for the singleton `knowledge_embedding_metadata` row.

  Tracks the embedding model and dimension that produced the vectors
  currently stored in `knowledge_entry_embeddings`. The public API is
  `Familiar.Knowledge.EmbeddingMetadata`; this module is just the schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "knowledge_embedding_metadata" do
    field :model_name, :string
    field :dimensions, :integer

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for updating the singleton row."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:model_name, :dimensions])
    |> validate_number(:dimensions, greater_than: 0)
  end
end
