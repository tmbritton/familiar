defmodule Familiar.Execution.WorkflowRunnerResumeTest do
  @moduledoc """
  Story 7.5-6 — `WorkflowRunner.resume_workflow/2` must pick up an
  interrupted run from the next incomplete step, with the outputs of
  the previously-completed steps visible in the resumed agent's
  task description.
  """

  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRuns

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()

    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      {:ok, List.duplicate(0.0, 768)}
    end)

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-10 12:00:00Z] end)

    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    Process.flag(:trap_exit, true)

    familiar_dir = new_tmp_dir()
    workflow_path = write_three_step_workflow(familiar_dir)

    {:ok, supervisor: sup, familiar_dir: familiar_dir, workflow_path: workflow_path}
  end

  describe "resume_workflow/2" do
    test "resumes from the step that failed and completes the run", ctx do
      # -- First pass: step 3 (polish/coder) fails --
      create_roles(ctx.familiar_dir, ~w(analyst builder))
      create_fail_role(ctx.familiar_dir, "polisher")

      # Counter lets the LLM mock flip behavior between the first run and the
      # resumed run without touching role files mid-test.
      flake_counter = :counters.new(1, [:atomics])

      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        role_name = extract_role(hd(messages).content)

        if role_name == "polisher" and :counters.get(flake_counter, 1) == 0 do
          {:error, {:provider_error, %{message: "first-run-fail"}}}
        else
          {:ok, %{content: "Result from #{role_name}"}}
        end
      end)

      assert {:error, {:step_failed, _}} =
               WorkflowRunner.run_workflow(ctx.workflow_path, %{task: "Build auth"},
                 familiar_dir: ctx.familiar_dir,
                 supervisor: ctx.supervisor
               )

      {:ok, [failed_run]} = WorkflowRuns.list(limit: 10)
      assert failed_run.status == "failed"
      assert failed_run.current_step_index == 2
      assert length(failed_run.step_results) == 2

      step_names = Enum.map(failed_run.step_results, & &1["step"])
      assert step_names == ["analyze", "build"]

      # -- Flip the polisher role to a normal one and resume --
      create_roles(ctx.familiar_dir, ~w(polisher))
      :counters.add(flake_counter, 1, 1)

      # Capture the task description the polisher agent sees on resume so we
      # can assert it contains the prior steps' outputs (AC7).
      captured_prompts =
        start_supervised!(
          {Agent, fn -> [] end},
          id: :resume_prompt_capture
        )

      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        role_name = extract_role(hd(messages).content)

        if role_name == "polisher" do
          Agent.update(captured_prompts, fn acc ->
            [Enum.map(messages, & &1.content) | acc]
          end)
        end

        {:ok, %{content: "Result from #{role_name}"}}
      end)

      assert {:ok, result} =
               WorkflowRunner.resume_workflow(failed_run.id,
                 familiar_dir: ctx.familiar_dir,
                 supervisor: ctx.supervisor
               )

      assert length(result.steps) == 3

      # Persisted row is now fully completed with all 3 step outputs
      {:ok, [completed_run]} = WorkflowRuns.list(limit: 10)
      assert completed_run.id == failed_run.id
      assert completed_run.status == "completed"
      assert completed_run.current_step_index == 3
      assert length(completed_run.step_results) == 3
      final_step_names = Enum.map(completed_run.step_results, & &1["step"])
      assert final_step_names == ["analyze", "build", "polish"]

      # AC7: the resumed polish step saw the outputs of analyze + build
      prompts = Agent.get(captured_prompts, & &1)
      assert length(prompts) == 1
      polisher_messages = hd(prompts) |> List.flatten()
      polisher_text = Enum.join(polisher_messages, "\n")
      assert polisher_text =~ "analyze"
      assert polisher_text =~ "build"
      assert polisher_text =~ "Result from analyst"
      assert polisher_text =~ "Result from builder"
    end

    test "returns :workflow_run_not_found for a missing id", _ctx do
      assert {:error, {:workflow_run_not_found, _}} =
               WorkflowRunner.resume_workflow(99_999)
    end

    test "refuses to resume a completed run", _ctx do
      {:ok, run} = WorkflowRuns.create("already-done")
      {:ok, _} = WorkflowRuns.complete(run.id)

      assert {:error, {:workflow_already_completed, %{id: id}}} =
               WorkflowRunner.resume_workflow(run.id)

      assert id == run.id
    end

    test "refuses to resume when workflow_path is missing", _ctx do
      {:ok, run} = WorkflowRuns.create("no-path")

      assert {:error, {:workflow_path_missing, %{id: id}}} =
               WorkflowRunner.resume_workflow(run.id)

      assert id == run.id
    end

    test "auto-finalizes rows whose index is past the last step", ctx do
      create_roles(ctx.familiar_dir, ~w(analyst builder polisher))

      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        role = extract_role(hd(messages).content)
        {:ok, %{content: "Result from #{role}"}}
      end)

      # Manually craft a row that is past the final step but still marked
      # running — simulates a crash between the last checkpoint and complete.
      {:ok, run} =
        WorkflowRuns.create("resume-demo",
          workflow_path: ctx.workflow_path,
          initial_context: %{"task" => "Recover"}
        )

      {:ok, _} =
        WorkflowRuns.checkpoint(run.id, 3, [
          %{"step" => "analyze", "output" => "ok"},
          %{"step" => "build", "output" => "ok"},
          %{"step" => "polish", "output" => "ok"}
        ])

      assert {:error, {:workflow_already_completed, _}} =
               WorkflowRunner.resume_workflow(run.id)

      # The row should now be marked completed as a side effect
      {:ok, reloaded} = WorkflowRuns.get(run.id)
      assert reloaded.status == "completed"
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
    dir = Path.join(System.tmp_dir!(), "wf_resume_test_#{System.unique_integer([:positive])}")
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

    You are a #{name}.
    """)
  end

  defp write_three_step_workflow(familiar_dir) do
    workflows_dir = Path.join(familiar_dir, "workflows")
    File.mkdir_p!(workflows_dir)

    path = Path.join(workflows_dir, "resume-demo.md")

    File.write!(path, """
    ---
    name: resume-demo
    description: Three-step workflow for resume tests
    steps:
      - name: analyze
        role: analyst
      - name: build
        role: builder
        input:
          - analyze
      - name: polish
        role: polisher
        input:
          - analyze
          - build
    ---

    Workflow body is unused; the test drives the runner directly.
    """)

    path
  end
end
