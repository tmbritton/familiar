defmodule Familiar.Knowledge.Entry do
  @moduledoc """
  Ecto schema for knowledge entries.

  Each entry represents a piece of natural language knowledge about the project:
  file summaries, conventions, architecture patterns, relationships, or decisions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(convention file_summary architecture relationship decision)
  @valid_sources ~w(init_scan post_task manual)

  schema "knowledge_entries" do
    field :text, :string
    field :type, :string
    field :source, :string
    field :source_file, :string
    field :metadata, :string, default: "{}"

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating or updating a knowledge entry."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:text, :type, :source, :source_file, :metadata])
    |> validate_required([:text, :type, :source])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:source, @valid_sources)
  end

  @doc "Returns the list of valid entry types."
  def valid_types, do: @valid_types

  @doc "Returns the list of valid sources."
  def valid_sources, do: @valid_sources
end
