defmodule Familiar.Daemon.PidFileTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.PidFile

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "write/0" do
    test "writes current OS PID to file" do
      assert {:ok, pid} = PidFile.write()
      assert pid == :os.getpid() |> to_string()
      assert File.exists?(Paths.daemon_pid_path())
      assert File.exists?(Paths.daemon_lock_path())
    end

    test "overwrites stale PID file for dead process" do
      Paths.ensure_familiar_dir!()
      File.write!(Paths.daemon_pid_path(), "999999")

      assert {:ok, _pid} = PidFile.write()
    end

    test "returns error when another daemon is running (current PID)" do
      {:ok, _} = PidFile.write()

      # Try to write again — current process is alive
      assert {:error, {:daemon_already_running, %{pid: _}}} = PidFile.write()
    end
  end

  describe "read/0" do
    test "reads PID from file" do
      {:ok, written_pid} = PidFile.write()
      assert {:ok, ^written_pid} = PidFile.read()
    end

    test "returns error when file doesn't exist" do
      assert {:error, {:not_found, %{}}} = PidFile.read()
    end

    test "returns error for malformed PID content" do
      Paths.ensure_familiar_dir!()
      File.write!(Paths.daemon_pid_path(), "not-a-number")

      assert {:error, {:invalid_config, %{reason: :malformed_pid}}} = PidFile.read()
    end

    test "returns error for negative PID" do
      Paths.ensure_familiar_dir!()
      File.write!(Paths.daemon_pid_path(), "-1")

      assert {:error, {:invalid_config, %{reason: :malformed_pid}}} = PidFile.read()
    end
  end

  describe "cleanup/0" do
    test "removes PID and lock files" do
      {:ok, _} = PidFile.write()
      assert File.exists?(Paths.daemon_pid_path())
      assert File.exists?(Paths.daemon_lock_path())

      PidFile.cleanup()
      refute File.exists?(Paths.daemon_pid_path())
      refute File.exists?(Paths.daemon_lock_path())
    end
  end

  describe "alive?/0" do
    test "returns true when PID file references current process" do
      {:ok, _} = PidFile.write()
      assert PidFile.alive?()
    end

    test "returns false when PID file doesn't exist" do
      refute PidFile.alive?()
    end

    test "returns false when PID file references dead process" do
      Paths.ensure_familiar_dir!()
      File.write!(Paths.daemon_pid_path(), "999999")

      refute PidFile.alive?()
    end
  end
end
