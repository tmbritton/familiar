defmodule Familiar.Planning.Engine do
  @moduledoc """
  Planning conversation engine.

  Orchestrates the planning flow: creates sessions, queries the Librarian
  for context, assembles prompts, calls the LLM, and persists messages.

  The CLI calls this module directly (in-process with the daemon).
  The Phoenix Channel (`FamiliarWeb.PlanningChannel`) provides WebSocket
  transport for external integrations. Both paths use the same Engine API.
  """

  require Logger

  import Ecto.Query

  alias Familiar.Knowledge.SecretFilter
  alias Familiar.Planning.Librarian
  alias Familiar.Planning.Message
  alias Familiar.Planning.PromptAssembly
  alias Familiar.Planning.Session
  alias Familiar.Repo

  # Story 3.2 will implement tool dispatch — currently tool_calls are
  # persisted for later verification but not executed during the conversation.
  @tool_definitions [
    %{
      name: "knowledge_search",
      description: "Search the project knowledge store for relevant context",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query"}
        },
        required: ["query"]
      }
    }
  ]

  @doc """
  Start a new planning conversation.

  Creates a session, queries the Librarian for context, assembles the prompt,
  calls the LLM, and persists all messages. Returns the first LLM response.

  Options:
  - `:providers_mod` — override Providers module (DI)
  - `:librarian_mod` — override Librarian module (DI)
  - `:librarian_opts` — options passed to Librarian.query (DI)
  """
  @spec start_plan(String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def start_plan(description, opts \\ []) do
    with {:ok, context} <- fetch_context(description, opts),
         {:ok, session} <- create_session(description, context),
         :ok <- insert_message(session.id, "user", description),
         {:ok, response} <- call_llm(session, opts) do
      {:ok, %{session_id: session.id, response: response, status: response_status(response)}}
    end
  end

  @doc """
  Send a user response to an active planning conversation.

  Loads the session and message history, appends the user message,
  re-assembles the prompt with full history, and calls the LLM.
  """
  @spec respond(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def respond(session_id, message, opts \\ []) do
    with {:ok, session} <- load_session(session_id),
         :ok <- validate_active(session),
         :ok <- insert_message(session_id, "user", message),
         {:ok, response} <- call_llm(session, opts) do
      {:ok, %{session_id: session.id, response: response, status: response_status(response)}}
    end
  end

  @doc """
  Resume a planning conversation.

  Loads the session and returns the current state (last assistant message
  and session metadata) so the user can continue.
  """
  @spec resume(integer()) :: {:ok, map()} | {:error, {atom(), map()}}
  def resume(session_id) do
    with {:ok, session} <- load_session(session_id) do
      messages = load_messages(session_id)
      last_assistant = messages |> Enum.filter(&(&1.role == "assistant")) |> List.last()

      {:ok,
       %{
         session_id: session.id,
         description: session.description,
         status: normalize_status(session.status),
         message_count: length(messages),
         last_response: if(last_assistant, do: last_assistant.content, else: nil)
       }}
    end
  end

  @doc """
  Find the latest active session.
  """
  @spec latest_active_session() :: {:ok, integer()} | {:error, {atom(), map()}}
  def latest_active_session do
    case from(s in Session, where: s.status == "active", order_by: [desc: s.id], limit: 1)
         |> Repo.one() do
      nil -> {:error, {:no_active_session, %{}}}
      session -> {:ok, session.id}
    end
  end

  @doc """
  Return tool definitions for the planning conversation.
  Used by Story 3.2 for verification against tool call logs.
  """
  @spec tool_definitions() :: [map()]
  def tool_definitions, do: @tool_definitions

  # -- Private --

  defp create_session(description, context) do
    %Session{}
    |> Session.changeset(%{description: description, context: context})
    |> Repo.insert()
    |> case do
      {:ok, session} -> {:ok, session}
      {:error, changeset} -> {:error, {:session_create_failed, %{changeset: changeset}}}
    end
  end

  defp load_session(session_id) do
    case Repo.get(Session, session_id) do
      nil -> {:error, {:session_not_found, %{session_id: session_id}}}
      session -> {:ok, session}
    end
  end

  defp validate_active(%Session{status: "active"}), do: :ok

  defp validate_active(%Session{status: status}) do
    {:error, {:session_not_active, %{status: status}}}
  end

  defp load_messages(session_id) do
    from(m in Message, where: m.session_id == ^session_id, order_by: [asc: m.inserted_at])
    |> Repo.all()
    |> Enum.map(fn m -> %{role: m.role, content: m.content} end)
  end

  defp fetch_context(description, opts) do
    librarian_mod = Keyword.get(opts, :librarian_mod, Librarian)
    librarian_opts = Keyword.get(opts, :librarian_opts, [])

    case librarian_mod.query(description, librarian_opts) do
      {:ok, %{summary: summary}} -> {:ok, summary}
      {:error, _} -> {:ok, nil}
    end
  end

  defp call_llm(session, opts) do
    providers = Keyword.get(opts, :providers_mod, Familiar.Providers)
    history = load_messages(session.id)

    {_system, messages} = PromptAssembly.assemble(session.context, history)

    case providers.chat(messages, tools: @tool_definitions) do
      {:ok, %{content: content} = response} ->
        tool_calls = Map.get(response, :tool_calls, [])
        persist_assistant_message(session, content, tool_calls)
        {:ok, content}

      {:error, reason} ->
        {:error, {:llm_failed, %{reason: reason}}}
    end
  end

  defp persist_assistant_message(session, content, tool_calls) do
    tool_calls_json = Jason.encode!(tool_calls || [])
    insert_message(session.id, "assistant", content, tool_calls_json)
  end

  # Best-effort persistence — conversation continues even if message
  # logging fails. This prevents transient DB issues from blocking
  # the planning flow. Failures are logged for diagnosis.
  defp insert_message(session_id, role, content, tool_calls \\ "[]") do
    filtered_content = SecretFilter.filter(content)

    %Message{}
    |> Message.changeset(%{
      session_id: session_id,
      role: role,
      content: filtered_content,
      tool_calls: tool_calls
    })
    |> Repo.insert()
    |> case do
      {:ok, _msg} -> :ok
      {:error, reason} ->
        Logger.warning("[Engine] Failed to persist message: #{inspect(reason)}")
        :ok
    end
  end

  # P10: Normalize all status returns to atoms for consistent API
  defp response_status(content) when is_binary(content) do
    if String.starts_with?(content, "[SPEC_READY]"), do: :spec_ready, else: :questioning
  end

  defp response_status(_), do: :questioning

  defp normalize_status("active"), do: :active
  defp normalize_status("completed"), do: :completed
  defp normalize_status("abandoned"), do: :abandoned
  defp normalize_status(other), do: String.to_atom(other)
end
