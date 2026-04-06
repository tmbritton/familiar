defmodule Familiar.CLI.WorkflowsExtensionsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths
  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRunner.Step
  alias Familiar.Execution.WorkflowRunner.Workflow

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  defp deps(overrides \\ []) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, Map.new(overrides))
  end

  # == list_workflows/1 ==

  describe "WorkflowRunner.list_workflows/1" do
    test "lists valid workflows from directory", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      workflows_dir = Path.join(familiar_dir, "workflows")
      File.mkdir_p!(workflows_dir)

      File.write!(Path.join(workflows_dir, "good.md"), """
      ---
      name: good-workflow
      description: A good workflow
      steps:
        - name: s1
          role: analyst
      ---
      Body.
      """)

      File.write!(Path.join(workflows_dir, "bad.md"), "no frontmatter")

      assert {:ok, workflows} = WorkflowRunner.list_workflows(familiar_dir: familiar_dir)
      assert length(workflows) == 1
      assert hd(workflows).name == "good-workflow"
    end

    test "returns empty list for missing directory" do
      assert {:ok, []} = WorkflowRunner.list_workflows(familiar_dir: "/nonexistent")
    end
  end

  # == fam workflows ==

  describe "fam workflows" do
    test "lists all workflows" do
      workflows = [
        %Workflow{
          name: "feature-planning",
          description: "Plan a feature",
          steps: [
            %Step{name: "research", role: "analyst"},
            %Step{name: "draft", role: "analyst"},
            %Step{name: "review", role: "reviewer"}
          ]
        },
        %Workflow{
          name: "task-fix",
          description: "Fix a bug",
          steps: [%Step{name: "diagnose", role: "analyst"}]
        }
      ]

      d = deps(list_workflows_fn: fn _opts -> {:ok, workflows} end)

      assert {:ok, %{workflows: result}} = Main.run({"workflows", [], %{}}, d)
      assert length(result) == 2

      planning = Enum.find(result, &(&1.name == "feature-planning"))
      assert planning.step_count == 3
      assert planning.description == "Plan a feature"
    end
  end

  describe "fam workflows <name>" do
    test "shows workflow details" do
      wf = %Workflow{
        name: "feature-planning",
        description: "Plan a feature",
        steps: [
          %Step{name: "research", role: "analyst", mode: :autonomous},
          %Step{name: "draft-spec", role: "analyst", mode: :interactive},
          %Step{name: "review", role: "reviewer", mode: :autonomous}
        ]
      }

      d = deps(parse_workflow_fn: fn _path -> {:ok, wf} end)

      assert {:ok, %{workflow: detail}} = Main.run({"workflows", ["feature-planning"], %{}}, d)
      assert detail.name == "feature-planning"
      assert length(detail.steps) == 3

      draft = Enum.find(detail.steps, &(&1.name == "draft-spec"))
      assert draft.role == "analyst"
      assert draft.mode == :interactive
    end

    test "returns error for unknown workflow" do
      d =
        deps(
          parse_workflow_fn: fn _path ->
            {:error, {:file_error, %{path: "/x.md", reason: :enoent}}}
          end
        )

      assert {:error, {:file_error, _}} = Main.run({"workflows", ["nope"], %{}}, d)
    end
  end

  # == fam extensions ==

  describe "fam extensions" do
    test "lists loaded extensions with tools" do
      d =
        deps(
          list_extensions_fn: fn ->
            {:ok,
             %{
               extensions: [
                 %{name: "safety", tools_count: 0, tools: []},
                 %{
                   name: "knowledge-store",
                   tools_count: 2,
                   tools: [:search_context, :store_context]
                 }
               ]
             }}
          end
        )

      assert {:ok, %{extensions: exts}} = Main.run({"extensions", [], %{}}, d)
      assert length(exts) == 2

      ks = Enum.find(exts, &(&1.name == "knowledge-store"))
      assert ks.tools_count == 2
    end
  end

  # == Output formatting ==

  describe "output formatting" do
    test "json mode returns workflows list" do
      result = {:ok, %{workflows: [%{name: "wf1", description: "D", step_count: 3}]}}
      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert [wf] = decoded["data"]["workflows"]
      assert wf["name"] == "wf1"
    end

    test "quiet mode for workflows list" do
      result = {:ok, %{workflows: [%{}, %{}]}}
      assert Output.format(result, :quiet) == "workflows:2"
    end

    test "quiet mode for workflow detail" do
      result = {:ok, %{workflow: %{name: "feature-planning", steps: [%{}, %{}, %{}]}}}
      assert Output.format(result, :quiet) == "workflow:feature-planning:3"
    end

    test "quiet mode for extensions" do
      result = {:ok, %{extensions: [%{}, %{}]}}
      assert Output.format(result, :quiet) == "extensions:2"
    end
  end
end
