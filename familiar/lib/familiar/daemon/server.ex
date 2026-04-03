defmodule Familiar.Daemon.Server do
  @moduledoc """
  Daemon lifecycle GenServer.

  Manages the daemon's runtime files (PID file, daemon.json, shutdown marker)
  and provides status/stop operations. Writes files on init, cleans up on
  terminate.
  """

  use GenServer

  require Logger

  alias Familiar.Daemon.PidFile
  alias Familiar.Daemon.ShutdownMarker
  alias Familiar.Daemon.StateFile

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get daemon status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Request graceful daemon shutdown."
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, configured_port())
    Process.flag(:trap_exit, true)

    case PidFile.write() do
      {:ok, pid} ->
        started_at = DateTime.utc_now() |> DateTime.to_iso8601()

        StateFile.write(%{port: port, pid: pid, started_at: started_at})
        ShutdownMarker.clear()

        Logger.info("[Daemon] Started on port #{port} (PID: #{pid})")

        {:ok, %{port: port, pid: pid, started_at: started_at}}

      {:error, {:daemon_already_running, %{pid: existing_pid}}} ->
        Logger.error("[Daemon] Another daemon is already running (PID: #{existing_pid})")
        {:stop, {:daemon_already_running, existing_pid}}

      {:error, {type, details}} ->
        Logger.error("[Daemon] Failed to acquire PID file: #{type} — #{inspect(details)}")
        {:stop, {type, details}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    Logger.info("[Daemon] Graceful shutdown requested")
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("[Daemon] Linked process #{inspect(pid)} exited: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[Daemon] Shutting down (reason: #{inspect(reason)})")
    # Notify extensions of shutdown before cleanup
    Familiar.Hooks.event(:on_shutdown, %{reason: reason})
    # Cleanup runtime files first, marker last (marker signals cleanup completed)
    StateFile.cleanup()
    PidFile.cleanup()
    ShutdownMarker.write()
    Logger.info("[Daemon] Cleanup complete (PID: #{state.pid})")
    :ok
  end

  # -- Private --

  defp configured_port do
    case Application.get_env(:familiar, FamiliarWeb.Endpoint) do
      nil -> 4000
      config -> get_in(config, [:http, :port]) || 4000
    end
  end
end
