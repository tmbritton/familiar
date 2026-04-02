defmodule Familiar.Planning.Session do
  @moduledoc """
  Ecto schema for planning sessions.

  Each session represents a single planning conversation initiated by
  `fam plan "description"`. Sessions are append-only — messages accumulate
  until the session is completed or abandoned.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(active completed abandoned)
  @max_description_length 4000

  schema "planning_sessions" do
    field :description, :string
    field :context, :string
    field :status, :string, default: "active"

    has_many :messages, Familiar.Planning.Message

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating or updating a planning session."
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:description, :context, :status])
    |> validate_required([:description])
    |> validate_length(:description, min: 1, max: @max_description_length)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Returns the list of valid session statuses."
  def valid_statuses, do: @valid_statuses
end
