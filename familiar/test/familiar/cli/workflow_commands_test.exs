defmodule Familiar.CLI.WorkflowCommandsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  # -- Helpers --

  defp workflow_deps(overrides \\ []) do
    %{
      ensure_running_fn:
        Keyword.get(overrides, :ensure_running_fn, fn _opts -> {:ok, 4000} end),
      health_fn:
        Keyword.get(overrides, :health_fn, fn _port ->
          {:ok, %{status: "ok", version: "0.1.0"}}
        end),
      daemon_status_fn:
        Keyword.get(overrides, :daemon_status_fn, fn _opts -> {:stopped, %{}} end),
      stop_daemon_fn:
        Keyword.get(overrides, :stop_daemon_fn, fn _opts ->
          {:error, {:daemon_unavailable, %{}}}
        end),
      workflow_fn:
        Keyword.get(overrides, :workflow_fn, fn _path, _context, _opts ->
          {:ok,
           %{
             steps: [
               %{step: "step1", output: "Output from step1"},
               %{step: "step2", output: "Output from step2"}
             ]
           }}
        end)
    }
  end

  # == parse_args ==

  describe "parse_args/1" do
    test "parses plan command with description" do
      assert {"plan", ["Add", "auth"], %{}} = Main.parse_args(["plan", "Add", "auth"])
    end

    test "parses do command with description" do
      assert {"do", ["Implement", "login"], %{}} = Main.parse_args(["do", "Implement", "login"])
    end

    test "parses fix command with description" do
      assert {"fix", ["broken", "redirect"], %{}} =
               Main.parse_args(["fix", "broken", "redirect"])
    end

    test "parses workflow commands with --json flag" do
      assert {"plan", ["auth"], %{json: true}} = Main.parse_args(["plan", "auth", "--json"])
    end
  end

  # == plan command ==

  describe "plan command" do
    test "dispatches to feature-planning workflow" do
      test_pid = self()

      deps =
        workflow_deps(
          workflow_fn: fn path, context, _opts ->
            send(test_pid, {:workflow_called, path, context})

            {:ok,
             %{steps: [%{step: "research", output: "Found patterns"}]}}
          end
        )

      assert {:ok, result} = Main.run({"plan", ["Add", "user", "auth"], %{}}, deps)
      assert result.workflow == "feature-planning"
      assert [%{step: "research", output: "Found patterns"}] = result.steps

      assert_receive {:workflow_called, path, context}
      assert path =~ "feature-planning.md"
      assert context == %{task: "Add user auth"}
    end

    test "returns usage error when no description given" do
      deps = workflow_deps()
      assert {:error, {:usage_error, %{message: msg}}} = Main.run({"plan", [], %{}}, deps)
      assert msg =~ "Usage: fam plan"
    end

    test "returns usage error for whitespace-only description" do
      deps = workflow_deps()

      assert {:error, {:usage_error, %{message: msg}}} =
               Main.run({"plan", ["   ", "  "], %{}}, deps)

      assert msg =~ "Usage: fam plan"
    end
  end

  # == do command ==

  describe "do command" do
    test "dispatches to feature-implementation workflow" do
      test_pid = self()

      deps =
        workflow_deps(
          workflow_fn: fn path, context, _opts ->
            send(test_pid, {:workflow_called, path, context})

            {:ok,
             %{
               steps: [
                 %{step: "implement", output: "Code written"},
                 %{step: "test", output: "Tests pass"},
                 %{step: "review", output: "LGTM"}
               ]
             }}
          end
        )

      assert {:ok, result} = Main.run({"do", ["Implement", "login"], %{}}, deps)
      assert result.workflow == "feature-implementation"
      assert length(result.steps) == 3

      assert_receive {:workflow_called, path, context}
      assert path =~ "feature-implementation.md"
      assert context == %{task: "Implement login"}
    end

    test "returns usage error when no description given" do
      deps = workflow_deps()
      assert {:error, {:usage_error, %{message: msg}}} = Main.run({"do", [], %{}}, deps)
      assert msg =~ "Usage: fam do"
    end
  end

  # == fix command ==

  describe "fix command" do
    test "dispatches to task-fix workflow" do
      test_pid = self()

      deps =
        workflow_deps(
          workflow_fn: fn path, context, _opts ->
            send(test_pid, {:workflow_called, path, context})

            {:ok,
             %{
               steps: [
                 %{step: "diagnose", output: "Root cause found"},
                 %{step: "fix", output: "Fix applied"},
                 %{step: "verify", output: "Tests pass"}
               ]
             }}
          end
        )

      assert {:ok, result} = Main.run({"fix", ["broken", "redirect"], %{}}, deps)
      assert result.workflow == "task-fix"
      assert length(result.steps) == 3

      assert_receive {:workflow_called, path, context}
      assert path =~ "task-fix.md"
      assert context == %{task: "broken redirect"}
    end

    test "returns usage error when no description given" do
      deps = workflow_deps()
      assert {:error, {:usage_error, %{message: msg}}} = Main.run({"fix", [], %{}}, deps)
      assert msg =~ "Usage: fam fix"
    end
  end

  # == error propagation ==

  describe "error propagation" do
    test "workflow failure propagates to CLI" do
      deps =
        workflow_deps(
          workflow_fn: fn _path, _context, _opts ->
            {:error, {:step_failed, %{step: "research", reason: "LLM error"}}}
          end
        )

      assert {:error, {:step_failed, %{step: "research"}}} =
               Main.run({"plan", ["something"], %{}}, deps)
    end

    test "file error propagates when workflow file missing" do
      deps =
        workflow_deps(
          workflow_fn: fn _path, _context, _opts ->
            {:error, {:file_error, %{path: "/nonexistent.md"}}}
          end
        )

      assert {:error, {:file_error, _}} = Main.run({"plan", ["something"], %{}}, deps)
    end
  end

  # == output formatting ==

  describe "output formatting" do
    test "result structure has workflow and steps keys" do
      deps = workflow_deps()

      assert {:ok, result} = Main.run({"plan", ["auth"], %{}}, deps)
      assert is_binary(result.workflow)
      assert is_list(result.steps)
      assert Enum.all?(result.steps, &(is_binary(&1.step) and is_binary(&1.output)))
    end

    test "json mode returns full result map" do
      result =
        {:ok,
         %{
           workflow: "task-fix",
           steps: [%{step: "diagnose", output: "Root cause"}]
         }}

      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["data"]["workflow"] == "task-fix"
      assert [step] = decoded["data"]["steps"]
      assert step["step"] == "diagnose"
    end

    test "quiet mode returns workflow summary" do
      result =
        {:ok,
         %{
           workflow: "feature-planning",
           steps: [%{step: "research", output: "done"}]
         }}

      output = Output.format(result, :quiet)
      assert output == "workflow:feature-planning:1"
    end
  end
end
