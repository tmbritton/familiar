defmodule Familiar.Daemon.ShutdownMarkerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.ShutdownMarker

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "write/0" do
    test "creates shutdown marker file" do
      Paths.ensure_familiar_dir!()
      ShutdownMarker.write()
      assert File.exists?(Paths.shutdown_marker_path())
    end
  end

  describe "exists?/0" do
    test "returns true when marker exists" do
      Paths.ensure_familiar_dir!()
      ShutdownMarker.write()
      assert ShutdownMarker.exists?()
    end

    test "returns false when marker doesn't exist" do
      refute ShutdownMarker.exists?()
    end
  end

  describe "clear/0" do
    test "removes the marker" do
      Paths.ensure_familiar_dir!()
      ShutdownMarker.write()
      assert ShutdownMarker.exists?()

      ShutdownMarker.clear()
      refute ShutdownMarker.exists?()
    end
  end

  describe "unclean_shutdown?/0" do
    test "returns false when .familiar/ doesn't exist" do
      refute ShutdownMarker.unclean_shutdown?()
    end

    test "returns true when .familiar/ exists but marker does not" do
      Paths.ensure_familiar_dir!()
      assert ShutdownMarker.unclean_shutdown?()
    end

    test "returns false when .familiar/ exists and marker exists" do
      Paths.ensure_familiar_dir!()
      ShutdownMarker.write()
      refute ShutdownMarker.unclean_shutdown?()
    end
  end
end
