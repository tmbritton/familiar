defmodule Familiar.Conversations.Conversation do
  @moduledoc """
  Ecto schema for agent conversations.

  Each conversation represents a multi-turn interaction — planning,
  implementation guidance, fix analysis, or any custom workflow step
  that involves back-and-forth with a user or between agents.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active completed abandoned)
  @max_description_length 4000

  schema "conversations" do
    field :description, :string
    field :context, :string
    field :status, :string, default: "active"
    field :scope, :string, default: "default"

    has_many :messages, Familiar.Conversations.Message

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating or updating a conversation."
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:description, :context, :status, :scope])
    |> validate_required([:description])
    |> validate_length(:description, min: 1, max: @max_description_length)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Returns the list of valid statuses."
  def valid_statuses, do: @valid_statuses
end
