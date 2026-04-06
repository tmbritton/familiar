defmodule Familiar.Conversations do
  @moduledoc """
  Harness-level conversation persistence.

  Provides multi-turn conversation history for any agent interaction —
  planning, implementation, fix, or custom workflows. This is execution
  infrastructure, not a workflow opinion.
  """

  use Boundary, deps: [], exports: [Familiar.Conversations]

  import Ecto.Query

  alias Familiar.Conversations.{Conversation, Message}
  alias Familiar.Repo

  @doc "Create a new conversation with a description and optional context."
  @spec create(String.t(), keyword()) :: {:ok, Conversation.t()} | {:error, {atom(), map()}}
  def create(description, opts \\ []) do
    context = Keyword.get(opts, :context)
    scope = Keyword.get(opts, :scope, "default")

    %Conversation{}
    |> Conversation.changeset(%{description: description, context: context, scope: scope})
    |> Repo.insert()
    |> case do
      {:ok, conv} -> {:ok, conv}
      {:error, cs} -> {:error, {:conversation_create_failed, %{changeset: cs}}}
    end
  end

  @doc "Fetch a conversation by ID."
  @spec get(integer()) :: {:ok, Conversation.t()} | {:error, {atom(), map()}}
  def get(id) do
    case Repo.get(Conversation, id) do
      nil -> {:error, {:conversation_not_found, %{id: id}}}
      conv -> {:ok, conv}
    end
  end

  @doc "Find the latest active conversation, optionally filtered by scope."
  @spec latest_active(keyword()) :: {:ok, integer()} | {:error, {atom(), map()}}
  def latest_active(opts \\ []) do
    scope = Keyword.get(opts, :scope)

    query =
      from(c in Conversation,
        where: c.status == "active",
        order_by: [desc: c.inserted_at],
        limit: 1,
        select: c.id
      )

    query = if scope, do: where(query, [c], c.scope == ^scope), else: query

    case Repo.one(query) do
      nil -> {:error, {:no_active_conversation, %{}}}
      id -> {:ok, id}
    end
  end

  @doc "Append a message to a conversation."
  @spec add_message(integer(), String.t(), String.t(), keyword()) ::
          {:ok, Message.t()} | {:error, {atom(), map()}}
  def add_message(conversation_id, role, content, opts \\ []) do
    tool_calls = Keyword.get(opts, :tool_calls, "[]")

    %Message{}
    |> Message.changeset(%{
      conversation_id: conversation_id,
      role: role,
      content: content,
      tool_calls: tool_calls
    })
    |> Repo.insert()
    |> case do
      {:ok, msg} -> {:ok, msg}
      {:error, cs} -> {:error, {:message_failed, %{changeset: cs}}}
    end
  end

  @doc "Load all messages for a conversation, ordered by insertion time."
  @spec messages(integer()) :: {:ok, [Message.t()]}
  def messages(conversation_id) do
    msgs =
      from(m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.inserted_at]
      )
      |> Repo.all()

    {:ok, msgs}
  end

  @doc "List conversations with optional scope and status filters, most recent first."
  @spec list(keyword()) :: {:ok, [Conversation.t()]}
  def list(opts \\ []) do
    scope = Keyword.get(opts, :scope)
    status = Keyword.get(opts, :status)

    query = from(c in Conversation, order_by: [desc: c.inserted_at])
    query = if scope, do: where(query, [c], c.scope == ^scope), else: query
    query = if status, do: where(query, [c], c.status == ^status), else: query

    {:ok, Repo.all(query)}
  end

  @doc "Count messages for a conversation."
  @spec message_count(integer()) :: non_neg_integer()
  def message_count(conversation_id) do
    from(m in Message, where: m.conversation_id == ^conversation_id, select: count())
    |> Repo.one()
  end

  @doc "Mark stale active conversations as abandoned. Default threshold: 24 hours."
  @spec cleanup_stale(keyword()) :: {:ok, %{cleaned: non_neg_integer()}}
  def cleanup_stale(opts \\ []) do
    hours = Keyword.get(opts, :max_age_hours, 24)
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    {count, _} =
      from(c in Conversation,
        where: c.status == "active" and c.inserted_at < ^cutoff
      )
      |> Repo.update_all(set: [status: "abandoned"])

    {:ok, %{cleaned: count}}
  end

  @doc "Update conversation status."
  @spec update_status(integer(), String.t()) ::
          {:ok, Conversation.t()} | {:error, {atom(), map()}}
  def update_status(id, new_status) do
    with {:ok, conv} <- get(id) do
      conv
      |> Conversation.changeset(%{status: new_status})
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, updated}
        {:error, cs} -> {:error, {:status_update_failed, %{changeset: cs}}}
      end
    end
  end
end
