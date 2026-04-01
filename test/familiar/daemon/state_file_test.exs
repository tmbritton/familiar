defmodule Familiar.Daemon.StateFileTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.StateFile

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "write/1" do
    test "writes state as JSON" do
      state = %{port: 4000, pid: "12345", started_at: "2026-04-01T00:00:00Z"}
      assert :ok = StateFile.write(state)
      assert File.exists?(Paths.daemon_json_path())
    end
  end

  describe "read/0" do
    test "reads and parses daemon.json" do
      state = %{port: 4000, pid: "12345", started_at: "2026-04-01T00:00:00Z"}
      StateFile.write(state)

      assert {:ok, read_state} = StateFile.read()
      assert read_state["port"] == 4000
      assert read_state["pid"] == "12345"
    end

    test "returns error when file doesn't exist" do
      assert {:error, {:not_found, %{}}} = StateFile.read()
    end

    test "returns error for invalid JSON" do
      Paths.ensure_familiar_dir!()
      File.write!(Paths.daemon_json_path(), "not json")

      assert {:error, {:invalid_config, %{reason: :invalid_json}}} = StateFile.read()
    end
  end

  describe "cleanup/0" do
    test "removes daemon.json" do
      StateFile.write(%{port: 4000, pid: "12345", started_at: "2026-04-01T00:00:00Z"})
      assert File.exists?(Paths.daemon_json_path())

      StateFile.cleanup()
      refute File.exists?(Paths.daemon_json_path())
    end
  end
end
