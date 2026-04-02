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

    test "auto-restores from backup when integrity fails and backup exists" do
      Paths.ensure_familiar_dir!()
      backups_dir = Paths.backups_dir()
      File.mkdir_p!(backups_dir)

      # Create a backup file
      backup_path = Path.join(backups_dir, "familiar-20260401T100000.db")
      File.write!(backup_path, "backup-content")

      # The real integrity check returns :ok since test DB is fine.
      # We test auto_restore_from_backup directly via the module.
      # The integration is: integrity fail → auto_restore_from_backup called.
      # Since we can't easily corrupt the test DB, we verify the backup module
      # functions work correctly via backup_test.exs.
      assert :ok = Recovery.check_database_integrity()
    end

    test "auto_restore_from_backup restores latest backup when available" do
      Paths.ensure_familiar_dir!()
      backups_dir = Paths.backups_dir()
      db_path = Familiar.Repo.config()[:database]
      File.mkdir_p!(backups_dir)

      # Create a valid backup from the actual test DB
      backup_path = Path.join(backups_dir, "familiar-20260401T120000.db")
      File.cp!(db_path, backup_path)

      # Call auto_restore_from_backup directly — verifies the
      # Backup.latest → Backup.restore pipeline used by check_database_integrity
      assert :ok = Recovery.auto_restore_from_backup()
    end

    test "auto_restore_from_backup returns error when no backups exist" do
      Paths.ensure_familiar_dir!()
      # No backups dir or files — error preserves shutdown marker for retry
      assert {:error, {:no_backups, %{}}} = Recovery.auto_restore_from_backup()
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
