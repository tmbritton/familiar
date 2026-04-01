defmodule Familiar.Daemon.ServerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.Server
  alias Familiar.Daemon.StateFile

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:familiar, :project_dir)

      # Stop server if still running (ignore if already stopped)
      try do
        if Process.whereis(Server), do: GenServer.stop(Server)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts and writes PID file and daemon.json" do
      {:ok, pid} = Server.start_link(port: 4567)
      assert Process.alive?(pid)

      assert File.exists?(Paths.daemon_pid_path())
      assert File.exists?(Paths.daemon_json_path())

      # Shutdown marker should be cleared
      refute File.exists?(Paths.shutdown_marker_path())

      GenServer.stop(pid)
    end

    test "writes correct port to daemon.json" do
      {:ok, pid} = Server.start_link(port: 9876)

      {:ok, state} = StateFile.read()
      assert state["port"] == 9876

      GenServer.stop(pid)
    end
  end

  describe "status/0" do
    test "returns daemon state" do
      {:ok, pid} = Server.start_link(port: 4567)

      assert {:ok, state} = Server.status()
      assert state.port == 4567
      assert is_binary(state.pid)
      assert is_binary(state.started_at)

      GenServer.stop(pid)
    end
  end

  describe "stop/0" do
    test "stops the daemon gracefully" do
      {:ok, pid} = Server.start_link(port: 4567)
      assert Process.alive?(pid)

      ref = Process.monitor(pid)
      assert :ok = Server.stop()
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "terminate/2" do
    test "writes shutdown marker and cleans up files" do
      {:ok, pid} = Server.start_link(port: 4567)

      assert File.exists?(Paths.daemon_pid_path())
      assert File.exists?(Paths.daemon_json_path())

      GenServer.stop(pid)

      # After clean shutdown: marker written, runtime files cleaned
      assert File.exists?(Paths.shutdown_marker_path())
      refute File.exists?(Paths.daemon_json_path())
      refute File.exists?(Paths.daemon_pid_path())
    end
  end
end
