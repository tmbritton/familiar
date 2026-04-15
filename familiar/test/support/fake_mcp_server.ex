defmodule Familiar.Test.FakeMCPServer do
  @moduledoc """
  Test double for an MCP server subprocess.

  Provides a FakePort GenServer that captures data "sent" to the server,
  plus helpers for simulating the MCP handshake and tool-call round-trips.

  Used by client_test.exs, mcp_client_test.exs, and mcp_integration_test.exs.
  """

  alias Familiar.MCP.Protocol

  # -- FakePort GenServer --

  defmodule FakePort do
    @moduledoc false
    use GenServer

    def start_link, do: GenServer.start_link(__MODULE__, [])
    def get_sent(port), do: GenServer.call(port, :get_sent)

    @impl true
    def init(_), do: {:ok, %{sent: []}}

    @impl true
    def handle_call(:get_sent, _from, state) do
      {:reply, Enum.reverse(state.sent), state}
    end

    @impl true
    def handle_info({:port_data, data}, state) do
      {:noreply, %{state | sent: [data | state.sent]}}
    end

    def handle_info(_msg, state), do: {:noreply, state}
  end

  # -- Message helpers --

  @doc "Send a JSON-RPC response line to the client as if from a port."
  def send_line(client, fake_port, json) do
    send(client, {fake_port, {:data, {:eol, json}}})
    Process.sleep(50)
  end

  @doc "Send an exit status to the client as if from a port."
  def send_exit(client, fake_port, code) do
    send(client, {fake_port, {:exit_status, code}})
    Process.sleep(50)
  end

  # -- Handshake helpers --

  @doc """
  Complete the MCP handshake (initialize + tools/list) with default tools.

  Options:
    * `:tools` — list of tool maps (default: `default_tools/0`)
    * `:server_name` — serverInfo name (default: `"test-server"`)
    * `:capabilities` — server capabilities (default: `%{"tools" => %{}}`)
  """
  def complete_handshake(client, fake_port, opts \\ []) do
    tools = Keyword.get(opts, :tools, default_tools())
    server_name = Keyword.get(opts, :server_name, "test-server")
    capabilities = Keyword.get(opts, :capabilities, %{"tools" => %{}})

    init_response =
      Protocol.encode_response(1, %{
        "protocolVersion" => "2025-11-05",
        "capabilities" => capabilities,
        "serverInfo" => %{"name" => server_name, "version" => "1.0"}
      })

    send_line(client, fake_port, init_response)

    tools_response = Protocol.encode_response(2, %{"tools" => tools})
    send_line(client, fake_port, tools_response)
  end

  @doc "Default two-tool set (read_data, write_data) for handshake."
  def default_tools do
    [
      %{
        "name" => "read_data",
        "description" => "Read data from source",
        "inputSchema" => %{"type" => "object"}
      },
      %{
        "name" => "write_data",
        "description" => "Write data to sink",
        "inputSchema" => %{"type" => "object"}
      }
    ]
  end

  # -- Port opener factories --

  @doc """
  Returns a port_opener function that creates a FakePort.

  The returned FakePort pid is only accessible via the client's internal state
  or by calling `FakePort.get_sent/1` on the pid returned from `start_client`.
  """
  def make_port_opener do
    fn _cmd, _args, _env ->
      {:ok, fake_port} = FakePort.start_link()
      send_fn = fn data -> send(fake_port, {:port_data, data}) end
      close_fn = fn -> :ok end
      {fake_port, send_fn, close_fn}
    end
  end

  @doc """
  Returns a port_opener that notifies `test_pid` with `{:fake_port_opened, fake_port}`
  when opened. Use with `receive_fake_port/1` to get the FakePort pid.
  """
  def make_port_opener_notify(test_pid) do
    fn _cmd, _args, _env ->
      {:ok, fake_port} = FakePort.start_link()
      send(test_pid, {:fake_port_opened, fake_port})
      send_fn = fn data -> send(fake_port, {:port_data, data}) end
      close_fn = fn -> :ok end
      {fake_port, send_fn, close_fn}
    end
  end

  @doc "Receive the FakePort pid sent by `make_port_opener_notify/1`."
  def receive_fake_port(timeout \\ 5_000) do
    receive do
      {:fake_port_opened, fake_port} -> fake_port
    after
      timeout -> raise "Timed out waiting for FakePort to be opened"
    end
  end
end
