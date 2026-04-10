defmodule Familiar.Execution.WorkflowRunnerPersistenceTest do
  @moduledoc """
  Story 7.5-6 — WorkflowRunner must checkpoint progress to the
  `workflow_runs` table at each step boundary so an interrupted run can
  be resumed from the next incomplete step.

  This test exercises the happy-path checkpoints; see
  `workflow_runner_resume_test.exs` for the failure-and-resume scenario.
  """

  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRuns

  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()

    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text -> {:ok, zero_vector()} end)

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-10 12:00:00Z] end)

    stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      role_name = extract_role(hd(messages).content)
      {:ok, %{content: "Result from #{role_name}"}}
    end)

    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    Process.flag(:trap_exit, true)

    familiar_dir = new_tmp_dir()
    create_roles(familiar_dir, ~w(analyst coder))
    workflow_path = write_two_step_workflow(familiar_dir)

    {:ok, supervisor: sup, familiar_dir: familiar_dir, workflow_path: workflow_path}
  end

  describe "persistence through a full run" do
    test "records start, checkpoints, and completion", ctx do
      assert {:ok, result} =
               WorkflowRunner.run_workflow(ctx.workflow_path, %{task: "Demo"},
                 familiar_dir: ctx.familiar_dir,
                 supervisor: ctx.supervisor
               )

      assert length(result.steps) == 2

      # There should be exactly one workflow_run row, marked completed
      {:ok, [run]} = WorkflowRuns.list(limit: 10)
      assert run.name == "persistence-demo"
      assert run.workflow_path == ctx.workflow_path
      assert run.status == "completed"
      assert run.current_step_index == 2
      assert length(run.step_results) == 2

      [first_checkpoint, second_checkpoint] = run.step_results
      assert first_checkpoint["step"] == "analyze"
      assert second_checkpoint["step"] == "build"
      assert first_checkpoint["output"] =~ "Result from analyst"
      assert second_checkpoint["output"] =~ "Result from coder"
      assert run.initial_context == %{"task" => "Demo"}
      assert run.last_error == nil
    end

    test "run_workflow_parsed without workflow_path still persists but is non-resumable", ctx do
      {:ok, workflow} = WorkflowRunner.parse(ctx.workflow_path)

      assert {:ok, _result} =
               WorkflowRunner.run_workflow_parsed(workflow, %{task: "NoPath"},
                 familiar_dir: ctx.familiar_dir,
                 supervisor: ctx.supervisor
               )

      {:ok, [run]} = WorkflowRuns.list(limit: 10)
      assert run.status == "completed"
      assert run.workflow_path == nil
    end
  end

  describe "safe_call/1 — fail-soft persistence wrapper" do
    test "returns the wrapped function's result on success" do
      assert {:ok, :done} = WorkflowRunner.safe_call(fn -> {:ok, :done} end)
      assert {:error, :nope} = WorkflowRunner.safe_call(fn -> {:error, :nope} end)
    end

    test "catches raised exceptions and wraps them in :persistence_exception" do
      assert {:error, {:persistence_exception, %RuntimeError{message: "boom"}}} =
               WorkflowRunner.safe_call(fn -> raise "boom" end)
    end

    test "catches ArgumentError from nil changeset cast" do
      # Simulates the shape of an actual failure from `Repo.update(nil)` if
      # `EmbeddingMetadata.set/2`-style piping ever saw a nil row.
      assert {:error, {:persistence_exception, %ArgumentError{}}} =
               WorkflowRunner.safe_call(fn -> raise ArgumentError, "bad cast" end)
    end

    test "catches :exit exits (e.g. Repo.Sandbox not running)" do
      assert {:error, {:persistence_exit, :no_repo}} =
               WorkflowRunner.safe_call(fn -> exit(:no_repo) end)
    end

    test "catches GenServer.call timeout exit shape" do
      assert {:error, {:persistence_exit, {:timeout, _}}} =
               WorkflowRunner.safe_call(fn ->
                 exit({:timeout, {:gen_server, :call, [:fake, :ping, 5000]}})
               end)
    end
  end

  describe "persistence on failure" do
    test "failed workflow is marked failed with last_error", ctx do
      # analyst is already created by the setup block; only overwrite coder
      # as the failing role.
      create_fail_role(ctx.familiar_dir, "coder")

      assert {:error, {:step_failed, _}} =
               WorkflowRunner.run_workflow(ctx.workflow_path, %{task: "Will fail"},
                 familiar_dir: ctx.familiar_dir,
                 supervisor: ctx.supervisor
               )

      {:ok, [run]} = WorkflowRuns.list(limit: 10)
      assert run.status == "failed"
      assert run.current_step_index == 1
      assert length(run.step_results) == 1
      assert hd(run.step_results)["step"] == "analyze"
      assert run.last_error =~ "step_failed"
    end
  end

  # -- Helpers --

  defp extract_role(content) do
    case Regex.run(~r/You are a ([a-z][a-z0-9 -]+)/, content) do
      [_, name] -> String.trim(name)
      _ -> "unknown"
    end
  end

  defp new_tmp_dir do
    dir =
      Path.join(System.tmp_dir!(), "wf_persist_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp create_roles(familiar_dir, names) do
    roles_dir = Path.join(familiar_dir, "roles")
    File.mkdir_p!(roles_dir)

    for name <- names do
      File.write!(Path.join(roles_dir, "#{name}.md"), """
      ---
      name: #{name}
      description: Test role for #{name}
      skills: []
      ---

      You are a #{name}. Complete your task and return the result.
      """)
    end
  end

  defp create_fail_role(familiar_dir, name) do
    roles_dir = Path.join(familiar_dir, "roles")
    File.mkdir_p!(roles_dir)

    File.write!(Path.join(roles_dir, "#{name}.md"), """
    ---
    name: #{name}
    description: Role that triggers failure
    skills: []
    ---

    FAIL_MODE You are a #{name} that will fail.
    """)

    # Override the global LLM stub so this role fails.
    stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      system = hd(messages)

      if system.content =~ "FAIL_MODE" do
        {:error, {:provider_error, %{message: "simulated"}}}
      else
        role_name = extract_role(system.content)
        {:ok, %{content: "Result from #{role_name}"}}
      end
    end)
  end

  defp write_two_step_workflow(familiar_dir) do
    workflows_dir = Path.join(familiar_dir, "workflows")
    File.mkdir_p!(workflows_dir)

    path = Path.join(workflows_dir, "persistence-demo.md")

    File.write!(path, """
    ---
    name: persistence-demo
    description: Two-step workflow used by persistence tests
    steps:
      - name: analyze
        role: analyst
      - name: build
        role: coder
    ---

    Workflow body is unused; the test drives the runner directly.
    """)

    path
  end
end
