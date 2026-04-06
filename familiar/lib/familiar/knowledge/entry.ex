defmodule Familiar.Knowledge.Entry do
  @moduledoc """
  Ecto schema for knowledge entries.

  Each entry represents a piece of natural language knowledge about the project:
  file summaries, conventions, architecture patterns, relationships, or decisions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_types ~w(convention file_summary architecture relationship decision fact gotcha)
  @valid_sources ~w(init_scan post_task manual agent user)

  schema "knowledge_entries" do
    field :text, :string
    field :type, :string
    field :source, :string
    field :source_file, :string
    field :metadata, :string, default: "{}"
    field :checked_at, :utc_datetime

    timestamps(type: :utc_datetime, autogenerate: {__MODULE__, :clock_now, []})
  end

  @doc false
  def clock_now do
    clock = Application.get_env(:familiar, Familiar.System.Clock, Familiar.System.RealClock)
    clock.now() |> DateTime.truncate(:second)
  end

  @doc "Changeset for creating or updating a knowledge entry."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:text, :type, :source, :source_file, :metadata, :checked_at])
    |> validate_required([:text, :type, :source])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_json(:metadata)
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

  @doc "Returns the list of valid entry types."
  def valid_types, do: @valid_types

  @doc "Returns the list of valid sources."
  def valid_sources, do: @valid_sources
end
