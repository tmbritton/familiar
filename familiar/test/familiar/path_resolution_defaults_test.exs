defmodule Familiar.PathResolutionDefaultsTest do
  @moduledoc """
  Verifies that modules which previously defaulted to `File.cwd!()` now
  resolve through `Familiar.Daemon.Paths.project_dir/0` when no explicit
  `:familiar_dir` / `:project_dir` option is passed.

  Uses `Application.put_env(:familiar, :project_dir, tmp_dir)` because
  `Paths.project_dir/0` reads that key before falling back to
  `FAMILIAR_PROJECT_DIR` or `File.cwd!/0`. Tests must run synchronously
  because the app env is shared global state.
  """

  use ExUnit.Case, async: false

  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Roles
  alias Familiar.Roles.Role

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:familiar, :project_dir)
    Application.put_env(:familiar, :project_dir, tmp_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:familiar, :project_dir, previous)
      else
        Application.delete_env(:familiar, :project_dir)
      end
    end)

    :ok
  end

  describe "Familiar.Roles default familiar_dir" do
    setup %{tmp_dir: tmp_dir} do
      roles_dir = Path.join([tmp_dir, ".familiar", "roles"])
      File.mkdir_p!(roles_dir)

      File.write!(Path.join(roles_dir, "coder.md"), """
      ---
      name: coder
      description: A coding agent
      model: sonnet
      lifecycle: session
      skills: []
      ---
      You are an expert coder.
      """)

      :ok
    end

    test "load_role/2 without :familiar_dir resolves via Paths.project_dir/0" do
      assert {:ok, %Role{name: "coder"}} = Roles.load_role("coder")
    end

    test "list_roles/1 without :familiar_dir resolves via Paths.project_dir/0" do
      assert {:ok, [%Role{name: "coder"}]} = Roles.list_roles()
    end
  end

  describe "WorkflowRunner.list_workflows/1 default familiar_dir" do
    setup %{tmp_dir: tmp_dir} do
      workflows_dir = Path.join([tmp_dir, ".familiar", "workflows"])
      File.mkdir_p!(workflows_dir)

      File.write!(Path.join(workflows_dir, "demo.md"), """
      ---
      name: demo
      description: A demo workflow
      steps:
        - name: do_it
          role: coder
      ---
      # Demo

      A trivial single-step workflow used only to verify default directory resolution.
      """)

      :ok
    end

    test "lists workflows from Paths.project_dir()/.familiar/workflows" do
      assert {:ok, workflows} = WorkflowRunner.list_workflows()
      assert Enum.any?(workflows, &(&1.name == "demo"))
    end
  end

  describe "Paths.project_dir/0 with Application.put_env override (legacy contract)" do
    # These tests verify that the 7.5-5 test-override pattern
    # (Application.put_env :familiar, :project_dir) still works after
    # Story 7.5-8 rewrote project_dir/0 to use resolve_project_dir/2.
    test "returns the Application env value as the resolved project_dir",
         %{tmp_dir: tmp_dir} do
      alias Familiar.Daemon.Paths
      assert Paths.project_dir() == Path.expand(tmp_dir)
      assert Paths.familiar_dir() == Path.join(Path.expand(tmp_dir), ".familiar")
    end
  end
end
