defmodule Familiar.Execution.AgentProcess do
  @moduledoc """
  Generic agent executor — one GenServer module for ALL agent roles.

  Loads a role from markdown, assembles prompts, and runs a tool-call
  loop against the configured LLM provider. Every tool call flows
  through `ToolRegistry.dispatch/3`, which enforces safety via the
  hooks pipeline.

  ## Lifecycle

  1. `init/1` — load role + skills, create conversation, broadcast `:on_agent_start`
  2. `handle_continue(:execute, state)` — kick off async LLM call
  3. Tool-call loop — dispatch tools, append results, call LLM again
  4. Completion — broadcast `:on_agent_complete`, notify parent, stop

  ## Safety Limits

  * Max tool calls per task (default: 100)
  * Per-task timeout (default: 5 minutes)
  """

  use GenServer, restart: :temporary

  require Logger

  alias Familiar.Activity
  alias Familiar.Conversations
  alias Familiar.Execution.PromptAssembly
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Hooks
  alias Familiar.Roles

  @default_max_tool_calls 100
  @default_task_timeout_ms 300_000

  # -- Public API --

  @doc """
  Start an agent process.

  ## Options

    * `:role` — role name string (required)
    * `:task` — task description string (required)
    * `:parent` — pid to notify on completion (optional)
    * `:familiar_dir` — path to `.familiar/` directory (optional)
    * `:max_tool_calls` — max tool calls before stopping (optional)
    * `:task_timeout_ms` — timeout in milliseconds (optional)
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Query the current status of an agent process."
  @spec status(pid()) :: {:ok, map()}
  def status(pid) do
    GenServer.call(pid, :status)
  end

  @doc "List all running agent processes under the AgentSupervisor."
  @spec list_agents() :: [{pid(), String.t()}]
  def list_agents do
    Familiar.Execution.AgentSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.reduce([], fn
      {:undefined, pid, :worker, _modules}, acc when is_pid(pid) ->
        try do
          case GenServer.call(pid, :agent_id, 5_000) do
            id when is_binary(id) -> [{pid, id} | acc]
            _ -> acc
          end
        catch
          :exit, _ -> acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  rescue
    e ->
      Logger.warning("[AgentProcess] list_agents failed: #{Exception.message(e)}")
      []
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    role_name = Keyword.fetch!(opts, :role)
    task = Keyword.fetch!(opts, :task)
    parent = Keyword.get(opts, :parent)
    familiar_dir_opts = Keyword.take(opts, [:familiar_dir])

    agent_id = "agent_#{System.unique_integer([:positive, :monotonic])}"

    case load_role_and_skills(role_name, familiar_dir_opts) do
      {:ok, role, skills} ->
        case Conversations.create("#{role_name}: #{task}", scope: "agent") do
          {:ok, conversation} ->
            timeout_ms = agent_config(:task_timeout_ms, opts, @default_task_timeout_ms)

            state = %{
              agent_id: agent_id,
              role: role,
              skills: skills,
              task: task,
              parent: parent,
              conversation_id: conversation.id,
              tool_call_count: 0,
              status: :running,
              started_at: System.monotonic_time(:millisecond),
              max_tool_calls: agent_config(:max_tool_calls, opts, @default_max_tool_calls),
              task_timeout_ms: timeout_ms,
              llm_task: nil,
              timeout_ref: nil,
              timeout_id: nil,
              messages: []
            }

            # Persist system + user messages for full conversation replay
            system_prompt = PromptAssembly.build_system_prompt(role, skills)
            log_add_message(Conversations.add_message(conversation.id, "system", system_prompt))
            log_add_message(Conversations.add_message(conversation.id, "user", task))

            Hooks.event(:on_agent_start, %{
              agent_id: agent_id,
              role: role_name,
              task: task
            })

            broadcast_activity(agent_id, :agent_started, role_name)
            notify_parent_started(state)

            {:ok, state, {:continue, :execute}}

          {:error, reason} ->
            {:stop, {:conversation_failed, reason}}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:execute, state) do
    start_llm_call(state)
  end

  @impl true
  def handle_call(:status, _from, state) do
    elapsed = System.monotonic_time(:millisecond) - state.started_at

    status = %{
      agent_id: state.agent_id,
      role: state.role.name,
      status: state.status,
      tool_calls: state.tool_call_count,
      elapsed_ms: elapsed
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:agent_id, _from, state) do
    {:reply, state.agent_id, state}
  end

  @impl true
  def handle_info({ref, result}, %{llm_task: %Task{ref: ref}} = state) do
    # Task completed — flush the :DOWN message
    Process.demonitor(ref, [:flush])
    cancel_timeout(state)

    case result do
      {:ok, response} ->
        handle_llm_response(response, state)

      {:error, reason} ->
        Logger.warning("[AgentProcess] LLM call failed: #{inspect(reason)}")
        complete_with_error(state, {:llm_error, reason})
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{llm_task: %Task{ref: ref}} = state) do
    cancel_timeout(state)
    Logger.warning("[AgentProcess] LLM task crashed: #{inspect(reason)}")
    complete_with_error(state, {:llm_error, {:task_crashed, reason}})
  end

  def handle_info({:task_timeout, timer_id}, %{status: :running, timeout_id: timer_id} = state) do
    # Only handle timeout if timer_id matches current — prevents stale timeouts
    if state.llm_task, do: Task.shutdown(state.llm_task, :brutal_kill)
    elapsed = System.monotonic_time(:millisecond) - state.started_at
    complete_with_error(%{state | llm_task: nil}, {:timeout, elapsed})
  end

  def handle_info({:task_timeout, _stale_id}, state) do
    # Stale timeout from a previous iteration — ignore
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # -- Private: LLM Call --

  defp start_llm_call(state) do
    elapsed = System.monotonic_time(:millisecond) - state.started_at

    if elapsed >= state.task_timeout_ms do
      complete_with_error(state, {:timeout, elapsed})
    else
      remaining_ms = state.task_timeout_ms - elapsed

      {messages, _tools, assembly_meta} =
        PromptAssembly.assemble(%{
          role: state.role,
          skills: state.skills,
          task: state.task,
          messages: Enum.reverse(state.messages)
        })

      if assembly_meta.truncated do
        Logger.info(
          "[AgentProcess] #{state.agent_id} prompt truncated: " <>
            "dropped #{length(assembly_meta.dropped_entries)} messages, " <>
            "budget=#{assembly_meta.token_budget.limit}, " <>
            "after=#{assembly_meta.token_budget.after_truncation}"
        )
      end

      broadcast_activity(state.agent_id, :llm_call, "iteration #{state.tool_call_count}")

      task =
        Task.Supervisor.async_nolink(
          Familiar.TaskSupervisor,
          fn -> Familiar.Providers.chat(messages, model: state.role.model) end
        )

      timer_id = make_ref()
      timeout_ref = Process.send_after(self(), {:task_timeout, timer_id}, remaining_ms)

      {:noreply, %{state | llm_task: task, timeout_ref: timeout_ref, timeout_id: timer_id}}
    end
  end

  defp cancel_timeout(state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
  end

  # -- Private: Response Handling --

  defp handle_llm_response(response, state) do
    content = Map.get(response, :content, "")
    tool_calls = Map.get(response, :tool_calls, [])

    # Persist assistant message
    tool_calls_json = if tool_calls == [], do: "[]", else: Jason.encode!(tool_calls)

    log_add_message(
      Conversations.add_message(
        state.conversation_id,
        "assistant",
        content || "",
        tool_calls: tool_calls_json
      )
    )

    assistant_msg = build_assistant_message(content, tool_calls)

    state = %{
      state
      | messages: [assistant_msg | state.messages],
        llm_task: nil,
        timeout_ref: nil,
        timeout_id: nil
    }

    if tool_calls == [] do
      complete_successfully(state, content)
    else
      dispatch_tool_calls(tool_calls, state)
    end
  end

  defp dispatch_tool_calls(tool_calls, state) do
    context = %{
      agent_id: state.agent_id,
      role: state.role.name,
      conversation_id: state.conversation_id,
      task_id: state.agent_id
    }

    {tool_messages_rev, new_count} =
      Enum.reduce(tool_calls, {[], state.tool_call_count}, fn tc, {msgs, count} ->
        {name, args} = extract_tool_call(tc)

        broadcast_activity(state.agent_id, :tool_call, to_string(name))

        result = dispatch_one_tool(name, args, context)
        result_content = format_tool_result(result)

        # Persist tool result
        log_add_message(Conversations.add_message(state.conversation_id, "tool", result_content))

        msg = %{role: "tool", content: result_content}
        {[msg | msgs], count + 1}
      end)

    state = %{
      state
      | messages: Enum.reverse(tool_messages_rev) ++ state.messages,
        tool_call_count: new_count
    }

    if new_count >= state.max_tool_calls do
      reason = {:max_tool_calls_exceeded, new_count}
      complete_with_error(state, reason)
    else
      start_llm_call(state)
    end
  end

  defp dispatch_one_tool(name, args, context) do
    case safe_to_existing_atom(name) do
      {:ok, atom_name} ->
        ToolRegistry.dispatch(atom_name, args, context)

      :error ->
        {:error, {:unknown_tool, name}}
    end
  end

  defp safe_to_existing_atom(name) when is_atom(name), do: {:ok, name}

  defp safe_to_existing_atom(name) when is_binary(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  # -- Private: Message Assembly --

  defp build_assistant_message(content, tool_calls) do
    base = %{role: "assistant", content: content || ""}
    if tool_calls == [], do: base, else: Map.put(base, :tool_calls, tool_calls)
  end

  # -- Private: Tool Call Parsing --

  defp extract_tool_call(tc) when is_map(tc) do
    case tc do
      %{"function" => %{"name" => name} = func} ->
        args = Map.get(func, "arguments", %{})
        {name, normalize_args(args)}

      %{function: %{name: name} = func} ->
        args = Map.get(func, :arguments, %{})
        {name, normalize_args(args)}

      %{"name" => name} ->
        args = Map.get(tc, "arguments", %{})
        {name, normalize_args(args)}

      %{name: name} ->
        args = Map.get(tc, :arguments, %{})
        {name, normalize_args(args)}

      _ ->
        {"unknown", %{}}
    end
  end

  defp normalize_args(args) when is_map(args) do
    # Keep keys as atoms only if they already exist — prevents atom table exhaustion
    # from arbitrary LLM-generated argument names
    Map.new(args, fn
      {k, v} when is_binary(k) ->
        atom_key =
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> k
          end

        {atom_key, v}

      {k, v} ->
        {k, v}
    end)
  end

  defp normalize_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, map} when is_map(map) -> normalize_args(map)
      _ -> %{}
    end
  end

  defp normalize_args(_), do: %{}

  # -- Private: Result Formatting --

  defp format_tool_result({:ok, result}) do
    Jason.encode!(%{ok: result})
  rescue
    _ -> inspect(result)
  end

  defp format_tool_result({:error, {:vetoed, reason}}) do
    "Tool call vetoed by safety policy: #{inspect(reason)}"
  end

  defp format_tool_result({:error, reason}) do
    "Error: #{inspect(reason)}"
  end

  # -- Private: Completion --

  defp complete_successfully(state, content) do
    Hooks.event(:on_agent_complete, %{
      agent_id: state.agent_id,
      role: state.role.name,
      result: content
    })

    Conversations.update_status(state.conversation_id, "completed")
    broadcast_activity(state.agent_id, :agent_complete, state.role.name)
    notify_parent(state, {:ok, content})

    {:stop, :normal, %{state | status: :completed}}
  end

  defp complete_with_error(state, reason) do
    Logger.warning(
      "[AgentProcess] Agent #{state.agent_id} (#{state.role.name}) failed: #{inspect(reason)}"
    )

    Hooks.event(:on_agent_error, %{
      agent_id: state.agent_id,
      role: state.role.name,
      error: reason
    })

    Conversations.update_status(state.conversation_id, "abandoned")
    broadcast_activity(state.agent_id, :agent_error, inspect(reason))
    notify_parent(state, {:error, reason})

    {:stop, :normal, %{state | status: :failed}}
  end

  defp notify_parent(%{parent: nil}, _result), do: :ok

  defp notify_parent(%{parent: pid, agent_id: id}, result),
    do: send(pid, {:agent_done, id, result})

  defp notify_parent_started(%{parent: nil}), do: :ok

  defp notify_parent_started(%{parent: pid, agent_id: id}),
    do: send(pid, {:agent_started, id, self()})

  defp log_add_message({:ok, _} = ok), do: ok

  defp log_add_message({:error, reason}),
    do: Logger.warning("[AgentProcess] add_message failed: #{inspect(reason)}")

  defp log_add_message(other), do: other

  # -- Private: Helpers --

  defp load_role_and_skills(role_name, opts) do
    case Roles.load_role(role_name, opts) do
      {:ok, role} ->
        skills = load_skills(role.skills, opts)
        {:ok, role, skills}

      {:error, _} = error ->
        error
    end
  end

  defp load_skills(skill_names, opts) do
    Enum.reduce(skill_names, [], fn skill_name, acc ->
      case Roles.load_skill(skill_name, opts) do
        {:ok, skill} ->
          [skill | acc]

        {:error, reason} ->
          Logger.warning(
            "[AgentProcess] Failed to load skill '#{skill_name}': #{inspect(reason)}"
          )

          acc
      end
    end)
    |> Enum.reverse()
  end

  defp agent_config(key, opts, default) do
    Keyword.get(
      opts,
      key,
      Application.get_env(:familiar, __MODULE__, []) |> Keyword.get(key, default)
    )
  end

  defp broadcast_activity(agent_id, type, detail) do
    Activity.broadcast(agent_id, %Activity.Event{
      type: type,
      detail: detail,
      timestamp: DateTime.utc_now()
    })
  end
end
