defmodule Familiar.MCP.ClientSupervisor do
  @moduledoc """
  DynamicSupervisor for MCP client connections.

  Each external MCP server gets its own `Familiar.MCP.Client` child
  process under this supervisor. Crash isolation ensures one failing
  MCP server doesn't take down others.
  """

  use DynamicSupervisor

  @doc "Start the MCP client supervisor."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start an MCP client child under the supervisor.

  ## Options

    * `:server_name` — unique MCP server name (required)
    * `:command` — executable path (required)
    * `:args` — command arguments (default `[]`)
    * `:env` — environment variables map (default `%{}`)
    * `:connect_timeout` — handshake timeout in ms (default 30_000)
    * `:call_timeout` — tool call timeout in ms (default 60_000)
  """
  @spec start_client(keyword()) :: DynamicSupervisor.on_start_child()
  def start_client(opts) do
    {supervisor, client_opts} = Keyword.pop(opts, :supervisor, __MODULE__)
    DynamicSupervisor.start_child(supervisor, {Familiar.MCP.Client, client_opts})
  end

  @doc "Stop an MCP client child by pid."
  @spec stop_client(GenServer.server(), pid()) :: :ok | {:error, :not_found}
  def stop_client(supervisor \\ __MODULE__, pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(supervisor, pid)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
