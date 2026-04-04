defmodule Familiar.Execution.ToolRegistry do
  @moduledoc """
  Central registry mapping tool names to Elixir implementations.

  Every tool call flows through `dispatch/3`, which runs the
  `before_tool_call` alter hook pipeline before execution and
  broadcasts `after_tool_call` on completion. This is the single
  chokepoint where safety enforcement intercepts tool calls.

  ## Built-in Tools

  The harness registers stub implementations for core tools at startup.
  Later stories replace stubs with real implementations:

    * File ops: `read_file`, `write_file`, `delete_file`, `list_files`, `search_files`
    * Shell: `run_command`
    * Agent orchestration: `spawn_agent`, `monitor_agents`, `broadcast_status`
    * Workflow: `signal_ready`
  """

  use GenServer

  require Logger

  alias Familiar.Hooks

  # -- Public API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a tool in the registry.

  Duplicate names overwrite the previous entry with a warning.
  """
  @spec register(atom(), function(), String.t(), String.t()) :: :ok
  def register(name, function, description, extension_name)
      when is_atom(name) and is_function(function, 2) and is_binary(description) and
             is_binary(extension_name) do
    GenServer.call(__MODULE__, {:register, name, function, description, extension_name})
  end

  @doc """
  Dispatch a tool call through the hooks pipeline.

  Flow: `before_tool_call` alter → execute tool → `after_tool_call` event.
  Returns `{:ok, result}`, `{:error, {:vetoed, reason}}`, or `{:error, reason}`.
  """
  @spec dispatch(atom(), map(), map()) :: {:ok, term()} | {:error, term()}
  def dispatch(name, args \\ %{}, context \\ %{}) when is_atom(name) do
    GenServer.call(__MODULE__, {:dispatch, name, args, context})
  end

  @doc "List all registered tools."
  @spec list_tools() :: [%{name: atom(), description: String.t(), extension: String.t()}]
  def list_tools do
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc "Get a specific tool entry."
  @spec get_tool(atom()) :: {:ok, map()} | {:error, {:unknown_tool, atom()}}
  def get_tool(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get_tool, name})
  end

  @doc """
  Export tool schemas for LLM tool-call prompt assembly.

  Returns a list of maps with `:name`, `:description`, and `:extension`.
  """
  @spec tool_schemas() :: [%{name: atom(), description: String.t(), extension: String.t()}]
  def tool_schemas do
    list_tools()
  end

  @doc """
  Register all core built-in tools.
  """
  @spec register_builtins() :: :ok
  def register_builtins do
    alias Familiar.Execution.Tools

    for {name, fun, description} <- builtin_tools() do
      register(name, fun, description, "harness")
    end

    :ok
  end

  # -- Server Callbacks --

  @impl true
  def init(_opts) do
    {:ok, %{tools: %{}}}
  end

  @impl true
  def handle_call({:register, name, function, description, extension_name}, _from, state) do
    if Map.has_key?(state.tools, name) do
      Logger.warning(
        "[ToolRegistry] Overwriting tool :#{name} " <>
          "(was #{state.tools[name].extension}, now #{extension_name})"
      )
    end

    entry = %{function: function, description: description, extension: extension_name}
    {:reply, :ok, %{state | tools: Map.put(state.tools, name, entry)}}
  end

  def handle_call({:dispatch, name, args, context}, from, state) do
    case prepare_dispatch(name, args, context, state) do
      {:execute, tool, payload} ->
        spawn_tool_execution(tool, payload, context, name, from)
        {:noreply, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:list_tools, _from, state) do
    tools =
      Enum.map(state.tools, fn {name, entry} ->
        %{name: name, description: entry.description, extension: entry.extension}
      end)

    {:reply, tools, state}
  end

  def handle_call({:get_tool, name}, _from, state) do
    case Map.fetch(state.tools, name) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      :error -> {:reply, {:error, {:unknown_tool, name}}, state}
    end
  end

  # -- Private --

  defp prepare_dispatch(name, args, context, state) do
    with {:ok, tool} <- fetch_tool(name, state),
         {:ok, payload} <- run_before_hook(name, args, context) do
      {:execute, tool, payload}
    end
  end

  defp spawn_tool_execution(tool, payload, context, name, from) do
    case Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
           result = execute_tool(tool, payload, context)
           GenServer.reply(from, result)
           broadcast_after_hook(name, payload.args, result)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning("[ToolRegistry] Failed to spawn tool task: #{inspect(reason)}")
        GenServer.reply(from, {:error, {:spawn_failed, reason}})
    end
  end

  defp fetch_tool(name, state) do
    case Map.fetch(state.tools, name) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, {:unknown_tool, name}}
    end
  end

  defp run_before_hook(name, args, context) do
    case Hooks.alter(:before_tool_call, %{tool: name, args: args}, context) do
      {:ok, modified_payload} -> {:ok, modified_payload}
      {:halt, reason} -> {:error, {:vetoed, reason}}
    end
  end

  defp execute_tool(tool, payload, context) do
    args = Map.get(payload, :args, %{})

    case tool.function.(args, context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}

      other ->
        Logger.warning("[ToolRegistry] Tool returned unexpected value: #{inspect(other)}")
        {:error, {:invalid_return, other}}
    end
  rescue
    error ->
      Logger.warning("[ToolRegistry] Tool crashed: #{Exception.message(error)}")
      {:error, {:tool_crashed, Exception.message(error)}}
  end

  defp broadcast_after_hook(name, args, result) do
    Hooks.event(:after_tool_call, %{tool: name, args: args, result: result})
  rescue
    _ -> :ok
  end

  defp builtin_tools do
    alias Familiar.Execution.Tools

    [
      {:read_file, &Tools.read_file/2, "Read the contents of a file at the given path"},
      {:write_file, &Tools.write_file/2, "Write content to a file at the given path"},
      {:delete_file, &Tools.delete_file/2, "Delete a file at the given path"},
      {:list_files, &Tools.list_files/2, "List files in a directory"},
      {:search_files, &Tools.search_files/2, "Search file contents for a pattern"},
      {:run_command, &Tools.run_command/2, "Run a shell command from the configured allow-list"},
      {:spawn_agent, &Tools.spawn_agent/2,
       "Spawn a child agent process with a given role and task"},
      {:run_workflow, &Tools.run_workflow/2,
       "Run a workflow defined in a markdown file with YAML frontmatter"},
      {:monitor_agents, &Tools.monitor_agents/2, "List running agent processes and their status"},
      {:broadcast_status, &Tools.broadcast_status/2,
       "Broadcast a status message to PubSub subscribers"},
      {:signal_ready, &Tools.signal_ready_stub/2,
       "Signal that the current workflow step is complete"}
    ]
  end
end
