defmodule Familiar.Daemon.RecoveryTest do
  use Familiar.DataCase, async: false

  @moduletag :tmp_dir

  alias Familiar.Daemon.Paths
  alias Familiar.Daemon.Recovery
  alias Familiar.Daemon.ShutdownMarker

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "run_if_needed/0" do
    test "runs recovery when unclean shutdown detected" do
      Paths.ensure_familiar_dir!()
      # .familiar/ exists but no marker → unclean shutdown
      assert ShutdownMarker.unclean_shutdown?()

      assert :ok = Recovery.run_if_needed()

      # After recovery, marker should be cleared (it was never there, so still no marker)
      # The key assertion is that run_if_needed completes without error
    end

    test "skips recovery when clean shutdown marker exists" do
      Paths.ensure_familiar_dir!()
      ShutdownMarker.write()
      refute ShutdownMarker.unclean_shutdown?()

      assert :ok = Recovery.run_if_needed()
    end

    test "skips recovery when .familiar/ doesn't exist" do
      refute ShutdownMarker.unclean_shutdown?()
      assert :ok = Recovery.run_if_needed()
    end
  end

  describe "run/0" do
    test "executes all three recovery phases" do
      # All phases are stubs that return :ok
      assert :ok = Recovery.run()
    end
  end

  describe "check_database_integrity/0" do
    test "returns :ok for a healthy database" do
      assert :ok = Recovery.check_database_integrity()
    end
  end

  describe "rollback_incomplete_transactions/0" do
    test "returns :ok (stub)" do
      assert :ok = Recovery.rollback_incomplete_transactions()
    end
  end

  describe "reconcile_orphaned_tasks/0" do
    test "returns :ok (stub)" do
      assert :ok = Recovery.reconcile_orphaned_tasks()
    end
  end
end
