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
  alias Familiar.Extensions.Safety
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

  describe "Familiar.Extensions.Safety default project_dir" do
    test "init/1 without :project_dir uses Paths.project_dir/0", %{tmp_dir: tmp_dir} do
      assert :ok = Safety.init([])

      # The sandbox should now accept paths under tmp_dir and reject paths
      # outside of it. A file inside the project directory should pass the
      # before_tool_call check; a file outside should be vetoed.
      inside_path = Path.join(tmp_dir, "inside.txt")

      outside_path =
        "/tmp/definitely-outside-the-project-#{System.unique_integer([:positive])}.txt"

      [hook] = Safety.hooks()
      handler = hook.handler

      inside_call = %{tool: :read_file, args: %{path: inside_path}}
      outside_call = %{tool: :read_file, args: %{path: outside_path}}
      context = %{}

      assert {:ok, ^inside_call} = handler.(inside_call, context)
      assert {:halt, "path_outside_project: " <> _} = handler.(outside_call, context)
    end
  end
end
