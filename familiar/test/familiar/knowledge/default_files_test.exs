defmodule Familiar.Knowledge.DefaultFilesTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Knowledge.DefaultFiles

  describe "install/1" do
    test "creates workflow files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = DefaultFiles.install(familiar_dir)

      workflows_dir = Path.join(familiar_dir, "workflows")
      assert File.dir?(workflows_dir)

      assert File.exists?(Path.join(workflows_dir, "feature-planning.md"))
      assert File.exists?(Path.join(workflows_dir, "feature-implementation.md"))
      assert File.exists?(Path.join(workflows_dir, "task-fix.md"))
    end

    test "creates role files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = DefaultFiles.install(familiar_dir)

      roles_dir = Path.join(familiar_dir, "roles")
      assert File.dir?(roles_dir)

      assert File.exists?(Path.join(roles_dir, "analyst.md"))
      assert File.exists?(Path.join(roles_dir, "coder.md"))
      assert File.exists?(Path.join(roles_dir, "reviewer.md"))
    end

    test "does not overwrite existing files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      workflows_dir = Path.join(familiar_dir, "workflows")
      File.mkdir_p!(workflows_dir)

      custom_content = "# My custom workflow"
      File.write!(Path.join(workflows_dir, "feature-planning.md"), custom_content)

      :ok = DefaultFiles.install(familiar_dir)

      assert File.read!(Path.join(workflows_dir, "feature-planning.md")) == custom_content
    end
  end
end
