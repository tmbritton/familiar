defmodule Familiar.System.FileUtilsTest do
  use ExUnit.Case, async: false
  use Familiar.MockCase

  alias Familiar.System.FileUtils

  describe "stat_check/3" do
    test "returns modified: true when file is newer than reference" do
      Mox.expect(Familiar.System.FileSystemMock, :stat, fn "test.md" ->
        {:ok, %{mtime: ~U[2026-04-03 12:00:00Z], size: 100}}
      end)

      assert {:ok, %{modified: true}} =
               FileUtils.stat_check("test.md", ~U[2026-04-03 10:00:00Z],
                 file_system: Familiar.System.FileSystemMock
               )
    end

    test "returns modified: false when file is older than reference" do
      Mox.expect(Familiar.System.FileSystemMock, :stat, fn "test.md" ->
        {:ok, %{mtime: ~U[2026-04-03 08:00:00Z], size: 100}}
      end)

      assert {:ok, %{modified: false}} =
               FileUtils.stat_check("test.md", ~U[2026-04-03 10:00:00Z],
                 file_system: Familiar.System.FileSystemMock
               )
    end

    test "returns modified: true when reference is nil" do
      Mox.expect(Familiar.System.FileSystemMock, :stat, fn "test.md" ->
        {:ok, %{mtime: ~U[2026-04-03 12:00:00Z], size: 100}}
      end)

      assert {:ok, %{modified: true}} =
               FileUtils.stat_check("test.md", nil, file_system: Familiar.System.FileSystemMock)
    end

    test "returns error for nil path" do
      assert {:error, {:no_file_path, %{}}} = FileUtils.stat_check(nil, nil)
    end

    test "returns file_missing error when stat fails" do
      Mox.expect(Familiar.System.FileSystemMock, :stat, fn "missing.md" ->
        {:error, :enoent}
      end)

      assert {:error, {:file_missing, %{path: "missing.md"}}} =
               FileUtils.stat_check("missing.md", nil,
                 file_system: Familiar.System.FileSystemMock
               )
    end
  end

  describe "open_in_editor/3" do
    test "opens file in editor and returns stat result" do
      Mox.expect(Familiar.System.ShellMock, :cmd, fn "vim", ["test.md"], [] ->
        {:ok, %{exit_code: 0, output: ""}}
      end)

      Mox.expect(Familiar.System.FileSystemMock, :stat, fn "test.md" ->
        {:ok, %{mtime: ~U[2026-04-03 12:00:00Z], size: 100}}
      end)

      assert {:ok, %{modified: true}} =
               FileUtils.open_in_editor("test.md", ~U[2026-04-03 10:00:00Z],
                 shell_mod: Familiar.System.ShellMock,
                 file_system: Familiar.System.FileSystemMock,
                 editor_env: "vim"
               )
    end

    test "returns error for nil path" do
      assert {:error, {:no_file_path, %{}}} = FileUtils.open_in_editor(nil, nil)
    end

    test "returns editor_failed for non-zero exit" do
      Mox.expect(Familiar.System.ShellMock, :cmd, fn "vim", ["test.md"], [] ->
        {:ok, %{exit_code: 1, output: ""}}
      end)

      assert {:error, {:editor_failed, %{exit_code: 1}}} =
               FileUtils.open_in_editor("test.md", nil,
                 shell_mod: Familiar.System.ShellMock,
                 editor_env: "vim"
               )
    end
  end

  describe "extract_body/1" do
    test "extracts body after frontmatter" do
      content = "---\ntitle: Test\nstatus: draft\n---\n\n# My Spec\n\nContent here"
      assert "# My Spec\n\nContent here" = FileUtils.extract_body(content)
    end

    test "returns full content when no frontmatter" do
      content = "# No Frontmatter\n\nJust content"
      assert content == FileUtils.extract_body(content)
    end
  end

  describe "read_body/2" do
    test "reads file and extracts body" do
      Mox.expect(Familiar.System.FileSystemMock, :read, fn "spec.md" ->
        {:ok, "---\ntitle: Test\n---\n\nBody content"}
      end)

      assert {:ok, "Body content"} =
               FileUtils.read_body("spec.md", file_system: Familiar.System.FileSystemMock)
    end

    test "returns error when file not found" do
      Mox.expect(Familiar.System.FileSystemMock, :read, fn "missing.md" ->
        {:error, :enoent}
      end)

      assert {:error, {:file_read_failed, _}} =
               FileUtils.read_body("missing.md", file_system: Familiar.System.FileSystemMock)
    end
  end

  describe "validate_path/1" do
    test "accepts relative paths" do
      assert FileUtils.validate_path("lib/my_file.ex") == :ok
    end

    test "accepts nested relative paths" do
      assert FileUtils.validate_path("src/components/button.tsx") == :ok
    end

    test "rejects absolute paths" do
      assert {:error, msg} = FileUtils.validate_path("/etc/passwd")
      assert msg =~ "relative"
    end

    test "rejects path traversal" do
      assert {:error, msg} = FileUtils.validate_path("../secret.txt")
      assert msg =~ "relative"
    end

    test "rejects embedded path traversal" do
      assert {:error, msg} = FileUtils.validate_path("lib/../../secret.txt")
      assert msg =~ "relative"
    end

    test "rejects empty string" do
      assert {:error, msg} = FileUtils.validate_path("")
      assert msg =~ "non-empty"
    end

    test "rejects nil" do
      assert {:error, msg} = FileUtils.validate_path(nil)
      assert msg =~ "non-empty"
    end
  end
end
