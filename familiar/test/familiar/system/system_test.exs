defmodule Familiar.System.SystemTest do
  use Familiar.MockCase

  alias Familiar.System.ClockMock
  alias Familiar.System.FileSystemMock
  alias Familiar.System.NotificationsMock
  alias Familiar.System.RealClock
  alias Familiar.System.ShellMock

  describe "FileSystem behaviour mock" do
    test "read/1 returns file contents" do
      expect(FileSystemMock, :read, fn path ->
        assert "/project/handler/song.go" = path
        {:ok, "package handler\n"}
      end)

      assert {:ok, "package handler\n"} = FileSystemMock.read("/project/handler/song.go")
    end

    test "write/2 succeeds" do
      expect(FileSystemMock, :write, fn _path, _content -> :ok end)
      assert :ok = FileSystemMock.write("/project/new_file.go", "content")
    end

    test "stat/1 returns file metadata" do
      expect(FileSystemMock, :stat, fn _path ->
        {:ok, %{mtime: ~U[2026-04-01 00:00:00Z], size: 1024}}
      end)

      assert {:ok, %{mtime: _, size: 1024}} = FileSystemMock.stat("/project/file.go")
    end

    test "delete/1 succeeds" do
      expect(FileSystemMock, :delete, fn _path -> :ok end)
      assert :ok = FileSystemMock.delete("/project/temp.go")
    end

    test "ls/1 returns directory listing" do
      expect(FileSystemMock, :ls, fn _path ->
        {:ok, ["file1.go", "file2.go"]}
      end)

      assert {:ok, ["file1.go", "file2.go"]} = FileSystemMock.ls("/project/handler/")
    end
  end

  describe "Shell behaviour mock" do
    test "cmd/3 returns command output" do
      expect(ShellMock, :cmd, fn command, args, _opts ->
        assert "go" = command
        assert ["test", "./..."] = args
        {:ok, %{output: "PASS\n", exit_code: 0}}
      end)

      assert {:ok, %{output: "PASS\n", exit_code: 0}} =
               ShellMock.cmd("go", ["test", "./..."], [])
    end
  end

  describe "Notifications behaviour mock" do
    test "notify/2 succeeds" do
      expect(NotificationsMock, :notify, fn title, body ->
        assert "Task Complete" = title
        assert "All 15 tasks finished" = body
        :ok
      end)

      assert :ok = NotificationsMock.notify("Task Complete", "All 15 tasks finished")
    end
  end

  describe "Clock behaviour mock" do
    test "now/0 returns frozen time" do
      frozen = ~U[2026-04-01 12:00:00Z]

      expect(ClockMock, :now, fn -> frozen end)

      assert ^frozen = ClockMock.now()
    end
  end

  describe "RealClock" do
    test "now/0 returns a DateTime close to current time" do
      before = DateTime.utc_now()
      result = RealClock.now()
      after_time = DateTime.utc_now()

      assert %DateTime{} = result
      assert DateTime.compare(result, before) in [:eq, :gt]
      assert DateTime.compare(result, after_time) in [:eq, :lt]
    end
  end
end
