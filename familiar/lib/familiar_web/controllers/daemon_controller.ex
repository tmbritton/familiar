defmodule FamiliarWeb.DaemonController do
  use FamiliarWeb, :controller

  alias Familiar.Daemon.Server

  @doc "Returns daemon status information."
  def status(conn, _params) do
    case get_server_status() do
      {:ok, state} ->
        json(conn, %{
          data: %{
            status: "running",
            port: state.port,
            pid: state.pid,
            started_at: state.started_at,
            uptime_seconds: uptime_seconds(state.started_at)
          }
        })

      :not_running ->
        json(conn, %{data: %{status: "stopped"}})
    end
  end

  @doc "Triggers graceful daemon shutdown."
  def stop(conn, _params) do
    case get_server_status() do
      {:ok, _state} ->
        Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
          Process.sleep(100)
          Server.stop()
        end)

        json(conn, %{data: %{status: "stopping"}})

      :not_running ->
        conn
        |> put_status(409)
        |> json(%{
          error: %{
            type: "daemon_unavailable",
            message: "No daemon running",
            details: %{}
          }
        })
    end
  end

  defp get_server_status do
    case Process.whereis(Server) do
      nil ->
        :not_running

      _pid ->
        try do
          Server.status()
        catch
          :exit, _ -> :not_running
        end
    end
  end

  defp uptime_seconds(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, start_time, _} ->
        DateTime.diff(DateTime.utc_now(), start_time, :second)

      _ ->
        0
    end
  end
end
