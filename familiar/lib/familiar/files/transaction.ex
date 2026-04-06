defmodule Familiar.Files.Transaction do
  @moduledoc """
  Ecto schema for file transaction records.

  Each record tracks a single file operation (write or delete) as part of
  the strict write sequence: log intent → write file → log completion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending completed rolled_back skipped conflict)

  schema "file_transactions" do
    field :task_id, :string
    field :file_path, :string
    field :content_hash, :string
    field :original_content_hash, :string
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:task_id, :file_path, :content_hash, :original_content_hash, :status])
    |> validate_required([:task_id, :file_path, :content_hash, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:task_id, :file_path])
  end

  @doc "Compute SHA-256 hex digest of content."
  @spec content_hash(binary()) :: String.t()
  def content_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
end
