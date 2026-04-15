defmodule Familiar.MCP.Client do
  @moduledoc """
  GenServer managing a single MCP server subprocess.

  Speaks JSON-RPC 2.0 over stdio (via Erlang Port) to an external MCP
  server. Performs the initialize handshake, discovers tools via
  `tools/list`, and registers them in `ToolRegistry`.

  ## Lifecycle

    1. `start_link/1` → `init/1` returns `:connecting`
    2. `handle_continue(:connect)` opens the Port, sends `initialize`
    3. Port data arrives → handshake completes → `tools/list` sent
    4. Tool list arrives → tools registered → status becomes `:connected`
    5. Tool calls flow through registered functions → `tools/call` JSON-RPC
    6. On port exit → tools unregistered → status becomes `:crashed`
  """

  use GenServer, restart: :transient

  require Logger

  alias Familiar.MCP.Protocol

  @default_connect_timeout 30_000
  @default_call_timeout 60_000
  @max_line_length 1_048_576

  @type status ::
          :connecting
          | :connected
          | :handshake_failed
          | :crashed
          | :disabled

  defstruct [
    :server_name,
    :command,
    :args,
    :env,
    :port,
    :port_opener,
    :send_fn,
    :close_fn,
    :connect_timeout,
    :call_timeout,
    :connect_timer,
    status: :connecting,
    status_reason: "initializing",
    next_id: 1,
    pending: %{},
    registered_tools: [],
    line_buffer: ""
  ]

  # -- Public API --

  @doc "Start an MCP client process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Get the current status of the client."
  @spec status(GenServer.server()) :: {status(), String.t()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc "Call a tool on the MCP server."
  @spec call_tool(GenServer.server(), String.t(), map(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def call_tool(server, tool_name, args \\ %{}, timeout \\ @default_call_timeout) do
    GenServer.call(server, {:call_tool, tool_name, args}, timeout + 5_000)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    server_name = Keyword.fetch!(opts, :server_name)
    command = Keyword.fetch!(opts, :command)

    state = %__MODULE__{
      server_name: server_name,
      command: command,
      args: Keyword.get(opts, :args, []),
      env: Keyword.get(opts, :env, %{}),
      port_opener: Keyword.get(opts, :port_opener),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      call_timeout: Keyword.get(opts, :call_timeout, @default_call_timeout)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case open_port(state) do
      {:ok, port, send_fn, close_fn} ->
        timer = Process.send_after(self(), :connect_timeout, state.connect_timeout)

        state = %{state | port: port, send_fn: send_fn, close_fn: close_fn, connect_timer: timer}
        {id, state} = next_id(state)

        initialize_params = %{
          "protocolVersion" => "2025-11-05",
          "capabilities" => %{},
          "clientInfo" => %{
            "name" => "familiar",
            "version" => app_version()
          }
        }

        send_request(state, id, "initialize", initialize_params)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "[MCP.Client:#{state.server_name}] Failed to open port: #{inspect(reason)}"
        )

        {:noreply,
         %{
           state
           | status: :handshake_failed,
             status_reason: "failed to open port: #{inspect(reason)}"
         }}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {state.status, state.status_reason}, state}
  end

  def handle_call({:call_tool, _tool_name, _args}, _from, %{status: status} = state)
      when status != :connected do
    {:reply,
     {:error, :tool_not_yet_available,
      "MCP server '#{state.server_name}' is #{status} (#{state.status_reason})"}, state}
  end

  def handle_call({:call_tool, tool_name, args}, from, state) do
    {id, state} = next_id(state)
    timer = Process.send_after(self(), {:call_timeout, id}, state.call_timeout)
    state = %{state | pending: Map.put(state.pending, id, {from, timer})}

    params = %{"name" => tool_name, "arguments" => args}
    send_request(state, id, "tools/call", params)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    full_line = state.line_buffer <> line
    state = %{state | line_buffer: ""}
    handle_line(full_line, state)
  end

  def handle_info({port, {:data, {:noeol, partial}}}, %{port: port} = state) do
    {:noreply, %{state | line_buffer: state.line_buffer <> partial}}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[MCP.Client:#{state.server_name}] Port exited with code #{code}")
    cancel_connect_timer(state)

    cancel_all_pending(
      state,
      {:error, :mcp_server_crashed, "MCP server exited with code #{code}"}
    )

    unregister_tools(state)

    {:noreply,
     %{state | port: nil, status: :crashed, status_reason: "exit code #{code}", pending: %{}}}
  end

  def handle_info(:connect_timeout, state) do
    Logger.warning("[MCP.Client:#{state.server_name}] Handshake timed out")
    cancel_all_pending(state, {:error, :timeout, "MCP handshake timed out"})
    close_port(state)

    {:noreply,
     %{
       state
       | status: :handshake_failed,
         status_reason: "timeout after #{state.connect_timeout}ms",
         port: nil,
         connect_timer: nil,
         pending: %{}
     }}
  end

  def handle_info({:call_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {{from, _timer}, pending} ->
        GenServer.reply(from, {:error, :timeout, "MCP tool call timed out"})
        {:noreply, %{state | pending: pending}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  # Ignore DOWN messages from port
  def handle_info({:EXIT, _port, _reason}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    # MCP has no session-level shutdown notification — just close the transport
    if state.send_fn, do: close_port(state)
    unregister_tools(state)
    :ok
  end

  # -- Private: Line Processing --

  defp handle_line("", state), do: {:noreply, state}

  defp handle_line(line, state) do
    case Protocol.decode(line) do
      {:ok, {:response, id, result}} ->
        handle_response(id, {:ok, result}, state)

      {:ok, {:error, id, _code, message, _data}} ->
        handle_response(id, {:error, :mcp_error, message}, state)

      {:ok, {:notification, _method, _params}} ->
        # Notifications from server are logged but not acted on for now
        {:noreply, state}

      {:ok, {:request, _id, _method, _params}} ->
        # Server-initiated requests not supported in client MVP
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[MCP.Client:#{state.server_name}] Failed to decode: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_response(id, result, state) do
    case Map.pop(state.pending, id) do
      {{from, timer}, pending} ->
        Process.cancel_timer(timer)
        state = %{state | pending: pending}
        handle_matched_response(id, result, from, state)

      {nil, _} ->
        # Could be the initialize response (id=1) which we handle specially
        handle_init_response(id, result, state)
    end
  end

  defp handle_matched_response(_id, result, from, state) do
    GenServer.reply(from, result)
    {:noreply, state}
  end

  defp handle_init_response(1, {:ok, _result}, state) do
    # Initialize succeeded — send initialized notification, then tools/list
    cancel_connect_timer(state)
    notification = Protocol.encode_notification("notifications/initialized")
    port_send(state, notification)

    {id, state} = next_id(state)
    # Set up a new connect timer for tools/list
    timer = Process.send_after(self(), :connect_timeout, state.connect_timeout)
    send_request(state, id, "tools/list", %{})
    {:noreply, %{state | connect_timer: timer}}
  end

  defp handle_init_response(1, {:error, _type, message}, state) do
    cancel_connect_timer(state)
    Logger.warning("[MCP.Client:#{state.server_name}] Initialize failed: #{message}")
    close_port(state)

    {:noreply,
     %{
       state
       | status: :handshake_failed,
         status_reason: "initialize error: #{message}",
         port: nil
     }}
  end

  defp handle_init_response(2, {:ok, result}, state) do
    # tools/list response
    cancel_connect_timer(state)
    tools = Map.get(result, "tools", [])
    registered = register_discovered_tools(state, tools)

    Logger.info(
      "[MCP.Client:#{state.server_name}] Connected, registered #{length(registered)} tools"
    )

    {:noreply,
     %{state | status: :connected, status_reason: "ready", registered_tools: registered}}
  end

  defp handle_init_response(2, {:error, _type, message}, state) do
    cancel_connect_timer(state)
    Logger.warning("[MCP.Client:#{state.server_name}] tools/list failed: #{message}")
    # Connected but no tools — still usable

    {:noreply,
     %{
       state
       | status: :connected,
         status_reason: "ready (no tools: #{message})",
         connect_timer: nil
     }}
  end

  defp handle_init_response(_id, _result, state) do
    {:noreply, state}
  end

  # -- Private: Tool Registration --

  defp register_discovered_tools(state, tools) do
    registry = Application.get_env(:familiar, :tool_registry, Familiar.Execution.ToolRegistry)
    client_pid = self()
    call_timeout = state.call_timeout

    Enum.map(tools, fn tool ->
      mcp_tool_name = tool["name"]
      tool_atom = String.to_atom("#{state.server_name}__#{mcp_tool_name}")
      description = tool["description"] || "MCP tool: #{mcp_tool_name}"
      extension_name = "mcp:#{state.server_name}"

      tool_fn = fn args, _context ->
        call_tool(client_pid, mcp_tool_name, args, call_timeout)
      end

      registry.register(tool_atom, tool_fn, description, extension_name)
      tool_atom
    end)
  end

  defp unregister_tools(state) do
    registry = Application.get_env(:familiar, :tool_registry, Familiar.Execution.ToolRegistry)

    Enum.each(state.registered_tools, fn tool_atom ->
      registry.unregister(tool_atom)
    end)
  end

  # -- Private: Port Management --

  defp open_port(state) do
    if state.port_opener do
      # DI for testing — caller provides a function that returns {port_ref, send_fn, close_fn}
      {port_ref, send_fn, close_fn} = state.port_opener.(state.command, state.args, state.env)
      {:ok, port_ref, send_fn, close_fn}
    else
      do_open_port(state)
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp do_open_port(state) do
    executable = resolve_executable(state.command)
    env = expand_env_map(state.env)

    port_opts = [
      :binary,
      :exit_status,
      {:line, @max_line_length},
      {:args, state.args},
      {:env, env}
    ]

    port = Port.open({:spawn_executable, executable}, port_opts)
    send_fn = fn data -> Port.command(port, [data, "\n"]) end
    close_fn = fn -> Port.close(port) end
    {:ok, port, send_fn, close_fn}
  end

  defp resolve_executable(command) do
    case System.find_executable(command) do
      nil -> raise "executable not found: #{command}"
      path -> String.to_charlist(path)
    end
  end

  defp expand_env_map(env) when is_map(env) do
    Enum.map(env, fn {key, value} ->
      expanded = Familiar.Config.expand_env(value)
      {String.to_charlist(to_string(key)), String.to_charlist(to_string(expanded))}
    end)
  end

  defp expand_env_map(_), do: []

  defp send_request(state, id, method, params) do
    json = Protocol.encode_request(id, method, params)
    port_send(state, json)
  end

  defp port_send(%{send_fn: send_fn}, data) when not is_nil(send_fn) do
    send_fn.(data)
  end

  defp port_send(_, _), do: :ok

  defp close_port(%{close_fn: close_fn}) when not is_nil(close_fn) do
    close_fn.()
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp close_port(_), do: :ok

  # -- Private: Helpers --

  defp next_id(state) do
    {state.next_id, %{state | next_id: state.next_id + 1}}
  end

  defp cancel_connect_timer(%{connect_timer: nil}), do: :ok

  defp cancel_connect_timer(%{connect_timer: timer}) do
    Process.cancel_timer(timer)
    :ok
  end

  defp cancel_all_pending(state, error) do
    Enum.each(state.pending, fn {_id, {from, timer}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, error)
    end)
  end

  defp app_version do
    case Application.spec(:familiar, :vsn) do
      nil -> "0.1.0"
      vsn -> to_string(vsn)
    end
  end
end
