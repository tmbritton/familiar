defmodule Familiar.Planning.Spec do
  @moduledoc """
  Ecto schema for generated feature specifications.

  Each spec is the output of a planning conversation — a verified markdown
  document with inline verification marks, convention annotations, and
  cited sources.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(draft approved rejected)

  schema "planning_specs" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :metadata, :string, default: "{}"
    field :file_path, :string

    belongs_to :session, Familiar.Planning.Session

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating or updating a spec."
  def changeset(spec, attrs) do
    spec
    |> cast(attrs, [:session_id, :title, :body, :status, :metadata, :file_path])
    |> validate_required([:session_id, :title, :body])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_json(:metadata)
    |> foreign_key_constraint(:session_id)
    |> unique_constraint(:session_id)
  end

  defp validate_json(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case Jason.decode(value) do
        {:ok, decoded} when is_map(decoded) -> []
        {:ok, _} -> [{field, "must be a JSON object"}]
        {:error, _} -> [{field, "must be valid JSON"}]
      end
    end)
  end

  @doc "Returns the list of valid spec statuses."
  def valid_statuses, do: @valid_statuses
end
