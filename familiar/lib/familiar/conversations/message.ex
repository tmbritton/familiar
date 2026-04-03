defmodule Familiar.Conversations.Message do
  @moduledoc """
  Ecto schema for conversation messages.

  Each message is one turn in a conversation — user input, assistant
  response, or system context. Messages are append-only within a
  conversation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_roles ~w(user assistant system tool)

  schema "conversation_messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, :string, default: "[]"

    belongs_to :conversation, Familiar.Conversations.Conversation

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Changeset for creating a message."
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :tool_calls])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_json(:tool_calls)
    |> foreign_key_constraint(:conversation_id)
  end

  defp validate_json(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case Jason.decode(value) do
        {:ok, decoded} when is_list(decoded) -> []
        {:ok, _} -> [{field, "must be a JSON array"}]
        {:error, _} -> [{field, "must be valid JSON"}]
      end
    end)
  end

  @doc "Returns the list of valid roles."
  def valid_roles, do: @valid_roles
end
