defmodule Familiar.Daemon.PathsTest do
  use ExUnit.Case, async: true

  alias Familiar.Daemon.Paths

  describe "path construction" do
    test "familiar_dir is under project_dir" do
      assert Paths.familiar_dir() == Path.join(Paths.project_dir(), ".familiar")
    end

    test "daemon_json_path is under familiar_dir" do
      assert Paths.daemon_json_path() == Path.join(Paths.familiar_dir(), "daemon.json")
    end

    test "daemon_pid_path is under familiar_dir" do
      assert Paths.daemon_pid_path() == Path.join(Paths.familiar_dir(), "daemon.pid")
    end

    test "daemon_lock_path is under familiar_dir" do
      assert Paths.daemon_lock_path() == Path.join(Paths.familiar_dir(), "daemon.lock")
    end

    test "shutdown_marker_path is under familiar_dir" do
      assert Paths.shutdown_marker_path() == Path.join(Paths.familiar_dir(), "shutdown_marker")
    end

    test "db_path is under familiar_dir" do
      assert Paths.db_path() == Path.join(Paths.familiar_dir(), "familiar.db")
    end
  end

  describe "ensure_familiar_dir!/0" do
    @tag :tmp_dir
    test "creates directory if it doesn't exist", %{tmp_dir: tmp_dir} do
      Application.put_env(:familiar, :project_dir, tmp_dir)

      on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)

      target = Path.join(tmp_dir, ".familiar")
      refute File.dir?(target)

      Paths.ensure_familiar_dir!()

      assert File.dir?(target)
    end
  end
end
