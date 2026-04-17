defmodule Familiar.Knowledge.Entry do
  @moduledoc """
  Ecto schema for knowledge entries.

  Each entry represents a piece of natural language knowledge about the project:
  file summaries, conventions, architecture patterns, relationships, or decisions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @default_types ~w(convention file_summary architecture relationship decision fact gotcha)
  @default_sources ~w(init_scan post_task manual agent user)
  @slug_format ~r/^[a-z][a-z0-9_]*$/

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
    |> validate_format(:type, @slug_format,
      message: "must start with a lowercase letter, followed by a-z, 0-9, or _"
    )
    |> validate_length(:type, min: 1, max: 50)
    |> validate_format(:source, @slug_format,
      message: "must start with a lowercase letter, followed by a-z, 0-9, or _"
    )
    |> validate_length(:source, min: 1, max: 50)
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

  @doc "Returns the default entry types used by init scan and extraction prompts."
  def default_types, do: @default_types

  @doc "Returns the default sources used by init scan and post-task hygiene."
  def default_sources, do: @default_sources

  @doc "Returns the slug format regex shared by Entry, Extractor, and Hygiene."
  def slug_format, do: @slug_format
end
