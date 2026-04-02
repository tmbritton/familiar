defmodule Familiar.Knowledge.BackupTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Knowledge.Backup

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)

    # Create a fake database file to back up
    db_dir = Path.join(tmp_dir, ".familiar")
    File.mkdir_p!(db_dir)
    db_path = Path.join(db_dir, "familiar.db")
    File.write!(db_path, "fake-sqlite-content")

    backups_dir = Path.join(db_dir, "backups")

    %{db_path: db_path, backups_dir: backups_dir}
  end

  describe "create/1" do
    test "creates a backup with timestamp filename", %{db_path: db_path, backups_dir: backups_dir} do
      assert {:ok, result} = Backup.create(db_path: db_path, backups_dir: backups_dir)
      assert result.path =~ "familiar-"
      assert result.path =~ ".db"
      assert result.size > 0
      assert result.filename =~ ~r/^familiar-\d{8}T\d{6}\.db$/
      assert File.exists?(result.path)
    end

    test "creates backups directory if it doesn't exist", %{
      db_path: db_path,
      backups_dir: backups_dir
    } do
      refute File.dir?(backups_dir)
      assert {:ok, _} = Backup.create(db_path: db_path, backups_dir: backups_dir)
      assert File.dir?(backups_dir)
    end

    test "returns error when source db doesn't exist", %{backups_dir: backups_dir} do
      assert {:error, {:backup_failed, %{reason: :source_not_found}}} =
               Backup.create(db_path: "/nonexistent/familiar.db", backups_dir: backups_dir)
    end
  end

  describe "list/1" do
    test "lists backups sorted newest first", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260401T100000.db"), "backup1")
      File.write!(Path.join(backups_dir, "familiar-20260402T100000.db"), "backup2")

      assert {:ok, backups} = Backup.list(backups_dir: backups_dir)
      assert length(backups) == 2
      assert hd(backups).filename == "familiar-20260402T100000.db"
      assert List.last(backups).filename == "familiar-20260401T100000.db"
    end

    test "ignores non-backup files", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260401T100000.db"), "backup")
      File.write!(Path.join(backups_dir, "random-file.txt"), "not a backup")

      assert {:ok, backups} = Backup.list(backups_dir: backups_dir)
      assert length(backups) == 1
    end

    test "returns empty list when no backups directory", %{backups_dir: backups_dir} do
      refute File.dir?(backups_dir)
      assert {:ok, []} = Backup.list(backups_dir: backups_dir)
    end

    test "returns empty list when no backup files", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      assert {:ok, []} = Backup.list(backups_dir: backups_dir)
    end

    test "includes size and timestamp in backup info", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260402T120000.db"), "content")

      assert {:ok, [backup]} = Backup.list(backups_dir: backups_dir)
      assert backup.size > 0
      assert backup.timestamp == "20260402T120000"
      assert backup.path =~ "familiar-20260402T120000.db"
    end
  end

  describe "restore/2" do
    test "restores database from backup", %{db_path: db_path, backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      backup_path = Path.join(backups_dir, "familiar-20260402T100000.db")
      File.write!(backup_path, "restored-content")

      assert :ok = Backup.restore(backup_path, db_path: db_path)
      assert File.read!(db_path) == "restored-content"
    end

    test "returns error when backup file doesn't exist", %{db_path: db_path} do
      assert {:error, {:backup_failed, %{reason: :source_not_found}}} =
               Backup.restore("/nonexistent/backup.db", db_path: db_path)
    end
  end

  describe "latest/1" do
    test "returns most recent backup path", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260401T100000.db"), "old")
      File.write!(Path.join(backups_dir, "familiar-20260402T100000.db"), "new")

      assert {:ok, path} = Backup.latest(backups_dir: backups_dir)
      assert path =~ "familiar-20260402T100000.db"
    end

    test "returns error when no backups exist", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      assert {:error, {:no_backups, %{}}} = Backup.latest(backups_dir: backups_dir)
    end
  end

  describe "prune/1" do
    test "deletes backups exceeding retention limit", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)

      for i <- 1..5 do
        File.write!(
          Path.join(backups_dir, "familiar-2026040#{i}T100000.db"),
          "backup#{i}"
        )
      end

      assert {:ok, result} = Backup.prune(backups_dir: backups_dir, retention: 3)
      assert result.deleted == 2
      assert result.kept == 3

      # Verify newest 3 kept, oldest 2 deleted
      assert {:ok, remaining} = Backup.list(backups_dir: backups_dir)
      assert length(remaining) == 3
      assert hd(remaining).filename == "familiar-20260405T100000.db"
    end

    test "does nothing when under retention limit", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      File.write!(Path.join(backups_dir, "familiar-20260401T100000.db"), "backup")

      assert {:ok, result} = Backup.prune(backups_dir: backups_dir, retention: 10)
      assert result.deleted == 0
      assert result.kept == 1
    end

    test "handles empty backups directory", %{backups_dir: backups_dir} do
      File.mkdir_p!(backups_dir)
      assert {:ok, %{deleted: 0, kept: 0}} = Backup.prune(backups_dir: backups_dir)
    end
  end
end
