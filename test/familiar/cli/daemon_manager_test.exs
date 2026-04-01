defmodule Familiar.CLI.DaemonManagerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.DaemonManager
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "daemon_status/1" do
    test "returns :stopped when no daemon.json exists" do
      health_fn = fn _port -> {:error, {:daemon_unavailable, %{}}} end
      assert {:stopped, _} = DaemonManager.daemon_status(health_fn: health_fn)
    end

    test "returns :running when daemon.json exists and health check passes" do
      write_daemon_json(4000)

      health_fn = fn 4000 -> {:ok, %{status: "ok", version: "0.1.0"}} end

      assert {:running, %{port: 4000, version: "0.1.0"}} =
               DaemonManager.daemon_status(health_fn: health_fn)
    end

    test "returns :stale when daemon.json exists but health check fails" do
      write_daemon_json(4000)

      health_fn = fn 4000 -> {:error, {:daemon_unavailable, %{}}} end
      assert {:stale, %{port: 4000}} = DaemonManager.daemon_status(health_fn: health_fn)
    end
  end

  describe "ensure_running/1" do
    test "returns port when daemon is already running" do
      write_daemon_json(4000)

      health_fn = fn 4000 -> {:ok, %{status: "ok", version: "0.1.0"}} end
      assert {:ok, 4000} = DaemonManager.ensure_running(health_fn: health_fn)
    end

    test "starts daemon when not running and waits for health" do
      started = :atomics.new(1, signed: false)
      port = 4567

      start_fn = fn ->
        :atomics.put(started, 1, 1)
        write_daemon_json(port)
        {:ok, port}
      end

      call_count = :atomics.new(1, signed: false)

      health_fn = fn ^port ->
        count = :atomics.add_get(call_count, 1, 1)

        if count >= 2 do
          {:ok, %{status: "ok", version: "0.1.0"}}
        else
          {:error, {:daemon_unavailable, %{}}}
        end
      end

      assert {:ok, ^port} =
               DaemonManager.ensure_running(
                 health_fn: health_fn,
                 start_fn: start_fn,
                 poll_interval: 10,
                 max_wait: 5_000
               )

      assert :atomics.get(started, 1) == 1
    end

    test "returns error when start fails" do
      start_fn = fn -> {:error, {:daemon_unavailable, %{reason: :start_failed}}} end
      health_fn = fn _port -> {:error, {:daemon_unavailable, %{}}} end

      assert {:error, {:daemon_unavailable, _}} =
               DaemonManager.ensure_running(
                 health_fn: health_fn,
                 start_fn: start_fn,
                 poll_interval: 10,
                 max_wait: 100
               )
    end
  end

  describe "stop_daemon/1" do
    test "sends stop via HTTP when daemon is running" do
      write_daemon_json(4000)

      stop_fn = fn 4000 -> {:ok, %{"status" => "stopping"}} end
      assert :ok = DaemonManager.stop_daemon(stop_fn: stop_fn)
    end

    test "returns error when no daemon is running" do
      stop_fn = fn _port -> {:error, {:daemon_unavailable, %{}}} end
      assert {:error, {:daemon_unavailable, _}} = DaemonManager.stop_daemon(stop_fn: stop_fn)
    end
  end

  # -- Helpers --

  defp write_daemon_json(port) do
    Paths.ensure_familiar_dir!()
    state = %{port: port, pid: to_string(:os.getpid()), started_at: "2026-04-01T00:00:00Z"}
    json = Jason.encode!(state)
    File.write!(Paths.daemon_json_path(), json)
  end
end
