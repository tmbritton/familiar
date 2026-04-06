defmodule Familiar.Execution.WorkflowRunnerTest do
  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRunner.Step
  alias Familiar.Execution.WorkflowRunner.Workflow
  alias Familiar.Knowledge.DefaultFiles

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()

    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      {:ok, List.duplicate(0.0, 768)}
    end)

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-04 12:00:00Z] end)

    # Default LLM stub — returns role-based response
    # For interactive steps: signals ready on second user message (only once)
    stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      system = hd(messages)

      if system.content =~ "FAIL_MODE" do
        {:error, {:provider_error, %{}}}
      else
        role_name = extract_role_from_system(system.content)
        user_msgs = Enum.count(messages, &(&1.role == "user"))
        tool_msgs = Enum.count(messages, &(&1.role == "tool"))

        # Signal ready on second user message, but only if we haven't already
        # (tool_msgs > 0 means signal_ready was already dispatched)
        if user_msgs >= 2 and tool_msgs == 0 do
          {:ok,
           %{
             content: "Result from #{role_name}",
             tool_calls: [%{"name" => "signal_ready", "arguments" => %{}}]
           }}
        else
          {:ok, %{content: "Result from #{role_name}"}}
        end
      end
    end)

    # Each test gets its own DynamicSupervisor for agent isolation
    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    Process.flag(:trap_exit, true)

    {:ok, supervisor: sup}
  end

  defp extract_role_from_system(content) do
    case Regex.run(~r/You are a ([a-z][a-z0-9 -]+)/, content) do
      [_, name] -> String.trim(name)
      _ -> "unknown"
    end
  end

  # -- Helpers --

  defp write_workflow(dir, name, yaml) do
    path = Path.join(dir, "#{name}.md")
    content = "---\n#{yaml}\n---\n\nWorkflow body.\n"
    File.write!(path, content)
    path
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "wf_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp ensure_signal_ready_registered do
    WorkflowRunner.register_signal_ready_tool()
  end

  defp stub_interactive_llm do
    ensure_signal_ready_registered()

    stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      build_interactive_llm_response(messages)
    end)
  end

  defp build_interactive_llm_response(messages) do
    system = hd(messages)

    if system.content =~ "FAIL_MODE" do
      {:error, {:provider_error, %{}}}
    else
      role_name = extract_role_from_system(system.content)
      user_msgs = Enum.count(messages, &(&1.role == "user"))
      tool_msgs = Enum.count(messages, &(&1.role == "tool"))
      maybe_signal_ready(role_name, user_msgs, tool_msgs)
    end
  end

  defp maybe_signal_ready(role_name, user_msgs, tool_msgs)
       when user_msgs >= 2 and tool_msgs == 0 do
    {:ok,
     %{
       content: "Result from #{role_name}",
       tool_calls: [%{"name" => "signal_ready", "arguments" => %{}}]
     }}
  end

  defp maybe_signal_ready(role_name, _user_msgs, _tool_msgs) do
    {:ok, %{content: "Result from #{role_name}"}}
  end

  defp create_role_files(familiar_dir, role_names) do
    roles_dir = Path.join(familiar_dir, "roles")
    File.mkdir_p!(roles_dir)

    for name <- role_names do
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
  end

  defp run_wf(workflow, context, test_ctx, extra_opts \\ [])

  defp run_wf(workflow, context, %{supervisor: sup} = test_ctx, extra_opts) do
    familiar_dir = Map.get(test_ctx, :familiar_dir, tmp_dir())

    opts =
      Keyword.merge(
        [familiar_dir: familiar_dir, supervisor: sup],
        extra_opts
      )

    WorkflowRunner.run_workflow_parsed(workflow, context, opts)
  end

  # == AC1: Workflow Parsing ==

  describe "parse/1" do
    test "parses valid workflow file" do
      dir = tmp_dir()

      path =
        write_workflow(dir, "test-wf", """
        name: test-workflow
        description: A test workflow
        steps:
          - name: step1
            role: analyst
          - name: step2
            role: coder
            mode: interactive
            input:
              - step1
        """)

      assert {:ok, workflow} = WorkflowRunner.parse(path)
      assert workflow.name == "test-workflow"
      assert workflow.description == "A test workflow"
      assert length(workflow.steps) == 2

      [s1, s2] = workflow.steps
      assert s1.name == "step1"
      assert s1.role == "analyst"
      assert s1.mode == :autonomous
      assert s1.input == []

      assert s2.name == "step2"
      assert s2.role == "coder"
      assert s2.mode == :interactive
      assert s2.input == ["step1"]
    end

    test "returns error for missing file" do
      assert {:error, {:file_error, _}} = WorkflowRunner.parse("/nonexistent.md")
    end

    test "returns error for malformed YAML" do
      dir = tmp_dir()
      path = Path.join(dir, "bad.md")
      File.write!(path, "no frontmatter here")

      assert {:error, {:malformed_yaml, _}} = WorkflowRunner.parse(path)
    end

    test "returns error for missing name" do
      dir = tmp_dir()

      path =
        write_workflow(dir, "no-name", """
        description: Missing name
        steps:
          - name: step1
            role: analyst
        """)

      assert {:error, {:invalid_workflow, "missing required field: name"}} =
               WorkflowRunner.parse(path)
    end

    test "returns error for missing steps" do
      dir = tmp_dir()
      path = write_workflow(dir, "no-steps", "name: incomplete\n")
      assert {:error, {:invalid_workflow, _}} = WorkflowRunner.parse(path)
    end

    test "returns error for step missing role" do
      dir = tmp_dir()

      path =
        write_workflow(dir, "bad-step", """
        name: bad-step
        steps:
          - name: step1
        """)

      assert {:error, {:invalid_step, _}} = WorkflowRunner.parse(path)
    end
  end

  # == AC2: Sequential Execution ==

  describe "sequential execution" do
    test "single-step workflow completes", ctx do
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["analyst"])

      workflow = %Workflow{
        name: "single-step",
        steps: [%Step{name: "analyze", role: "analyst"}]
      }

      assert {:ok, result} =
               run_wf(workflow, %{task: "Analyze"}, Map.put(ctx, :familiar_dir, familiar_dir))

      assert [%{step: "analyze", output: output}] = result.steps
      assert output =~ "Result from analyst"
    end

    test "multi-step workflow executes in sequence", ctx do
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["analyst", "coder"])

      workflow = %Workflow{
        name: "multi-step",
        steps: [
          %Step{name: "analyze", role: "analyst"},
          %Step{name: "implement", role: "coder", input: ["analyze"]}
        ]
      }

      assert {:ok, result} =
               run_wf(workflow, %{task: "Build"}, Map.put(ctx, :familiar_dir, familiar_dir))

      assert length(result.steps) == 2
      assert Enum.at(result.steps, 0).output =~ "Result from analyst"
      assert Enum.at(result.steps, 1).output =~ "Result from coder"
    end
  end

  # == AC3: Context Accumulation ==

  describe "context accumulation" do
    test "previous step output appears in next step's task", ctx do
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["step-a", "step-b"])

      Familiar.Providers.LLMMock
      |> stub(:chat, fn messages, _opts ->
        system = hd(messages)
        task_msg = Enum.find(messages, &(&1.role == "user"))

        if system.content =~ "step-b" do
          if task_msg.content =~ "Result from step-a" do
            {:ok, %{content: "step-b saw context"}}
          else
            {:ok, %{content: "step-b missing context"}}
          end
        else
          {:ok, %{content: "Result from step-a"}}
        end
      end)

      workflow = %Workflow{
        name: "context-test",
        steps: [
          %Step{name: "sa", role: "step-a"},
          %Step{name: "sb", role: "step-b"}
        ]
      }

      assert {:ok, result} =
               run_wf(workflow, %{}, Map.put(ctx, :familiar_dir, familiar_dir))

      assert Enum.at(result.steps, 1).output == "step-b saw context"
    end
  end

  # == AC4: signal_ready Tool ==

  describe "signal_ready" do
    test "tool returns acknowledged when runner exists" do
      ensure_registry()
      :ets.insert(:familiar_workflow_registry, {"test_agent_1", self()})

      assert {:ok, %{status: "acknowledged"}} =
               WorkflowRunner.signal_ready_tool(%{}, %{agent_id: "test_agent_1"})

      assert_receive {:signal_ready, "test_agent_1"}
      :ets.delete(:familiar_workflow_registry, "test_agent_1")
    end

    test "tool returns no_workflow when no runner" do
      assert {:ok, %{status: "no_workflow"}} =
               WorkflowRunner.signal_ready_tool(%{}, %{agent_id: "orphan_agent"})
    end

    defp ensure_registry do
      if :ets.whereis(:familiar_workflow_registry) == :undefined do
        :ets.new(:familiar_workflow_registry, [:set, :named_table, :public])
      end
    rescue
      ArgumentError -> :ok
    end
  end

  # == AC5: Step Failure ==

  describe "step failure" do
    test "agent error stops workflow", ctx do
      familiar_dir = tmp_dir()
      create_fail_role(familiar_dir, "fail-agent")

      workflow = %Workflow{
        name: "fail-test",
        steps: [%Step{name: "fail-step", role: "fail-agent"}]
      }

      assert {:error, {:step_failed, %{step: "fail-step"}}} =
               run_wf(workflow, %{task: "fail"}, Map.put(ctx, :familiar_dir, familiar_dir))
    end

    test "multi-step stops on first failure", ctx do
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["analyst"])
      create_fail_role(familiar_dir, "fail-agent")

      workflow = %Workflow{
        name: "partial-fail",
        steps: [
          %Step{name: "s1", role: "analyst"},
          %Step{name: "s2", role: "fail-agent"}
        ]
      }

      assert {:error, {:step_failed, %{step: "s2"}}} =
               run_wf(workflow, %{}, Map.put(ctx, :familiar_dir, familiar_dir))
    end
  end

  # == AC6: Status ==

  describe "status/1" do
    test "returns pending status before run" do
      workflow = %Workflow{
        name: "status-test",
        steps: [%Step{name: "s1", role: "analyst"}]
      }

      {:ok, pid} = WorkflowRunner.start_link(workflow: workflow)
      status = WorkflowRunner.status(pid)

      assert status.workflow == "status-test"
      assert status.status == :pending
      assert status.completed_steps == 0
      assert status.total_steps == 1
    end
  end

  # == AC7: run_workflow convenience ==

  describe "run_workflow/3" do
    test "parses and runs from file", ctx do
      dir = tmp_dir()
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["worker"])

      path =
        write_workflow(dir, "conv", """
        name: convenience-test
        steps:
          - name: work
            role: worker
        """)

      assert {:ok, result} =
               WorkflowRunner.run_workflow(path, %{task: "do work"},
                 familiar_dir: familiar_dir,
                 supervisor: ctx.supervisor
               )

      assert [%{step: "work", output: output}] = result.steps
      assert output =~ "Result from worker"
    end

    test "returns parse error for invalid file" do
      assert {:error, {:file_error, _}} = WorkflowRunner.run_workflow("/nonexistent.md")
    end
  end

  describe "default workflow execution" do
    @tag timeout: 15_000
    test "feature-planning workflow runs end-to-end with default files", ctx do
      stub_interactive_llm()
      familiar_dir = setup_default_files()
      path = Path.join([familiar_dir, "workflows", "feature-planning.md"])

      # Auto-complete interactive steps by always signaling ready
      input_fn = fn _step, _content -> {:ok, "User response"} end

      assert {:ok, result} =
               WorkflowRunner.run_workflow(
                 path,
                 %{task: "Plan a user authentication feature"},
                 familiar_dir: familiar_dir,
                 supervisor: ctx.supervisor,
                 timeout_ms: 10_000,
                 input_fn: input_fn
               )

      assert length(result.steps) == 3

      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["research", "draft-spec", "review-spec"]

      for step <- result.steps do
        assert is_binary(step.output) and step.output != ""
      end
    end

    test "feature-implementation workflow runs end-to-end with default files", ctx do
      familiar_dir = setup_default_files()

      path = Path.join([familiar_dir, "workflows", "feature-implementation.md"])

      assert {:ok, result} =
               WorkflowRunner.run_workflow(
                 path,
                 %{task: "Implement login form"},
                 familiar_dir: familiar_dir,
                 supervisor: ctx.supervisor
               )

      assert length(result.steps) == 3

      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["implement", "test", "review"]
    end

    test "task-fix workflow runs end-to-end with default files", ctx do
      familiar_dir = setup_default_files()

      path = Path.join([familiar_dir, "workflows", "task-fix.md"])

      assert {:ok, result} =
               WorkflowRunner.run_workflow(
                 path,
                 %{task: "Fix broken login redirect"},
                 familiar_dir: familiar_dir,
                 supervisor: ctx.supervisor
               )

      assert length(result.steps) == 3

      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["diagnose", "fix", "verify"]
    end

    test "later steps receive context from prior steps via input references", ctx do
      stub_interactive_llm()
      familiar_dir = setup_default_files()

      # Track what messages each agent receives
      test_pid = self()

      Familiar.Providers.LLMMock
      |> stub(:chat, fn messages, _opts ->
        user_msg = Enum.find(messages, &(&1.role == "user"))

        if user_msg && user_msg.content =~ "Step: draft-spec" do
          send(test_pid, {:draft_spec_context, user_msg.content})
        end

        role_name = extract_role_from_system(hd(messages).content)
        user_msgs = Enum.count(messages, &(&1.role == "user"))

        if user_msgs >= 2 do
          {:ok,
           %{
             content: "Output from #{role_name} step",
             tool_calls: [%{"name" => "signal_ready", "arguments" => %{}}]
           }}
        else
          {:ok, %{content: "Output from #{role_name} step"}}
        end
      end)

      input_fn = fn _step, _content -> {:ok, "User input"} end
      path = Path.join([familiar_dir, "workflows", "feature-planning.md"])

      assert {:ok, _result} =
               WorkflowRunner.run_workflow(
                 path,
                 %{task: "Plan feature X"},
                 familiar_dir: familiar_dir,
                 supervisor: ctx.supervisor,
                 input_fn: input_fn
               )

      assert_receive {:draft_spec_context, context}, 5_000
      assert context =~ "research:"
      assert context =~ "Output from"
    end
  end

  # == Interactive Mode ==

  describe "interactive mode" do
    test "interactive step sends needs_input and accepts user response", ctx do
      stub_interactive_llm()
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["interactive-agent"])

      # Mock LLM: first call returns a question, second call (after user input) signals ready
      Familiar.Providers.LLMMock
      |> stub(:chat, fn messages, _opts ->
        user_msgs = Enum.count(messages, &(&1.role == "user"))

        if user_msgs >= 2 do
          # User responded — signal ready with final output
          {:ok,
           %{
             content: "Great, I'll use blue.",
             tool_calls: [%{"name" => "signal_ready", "arguments" => %{}}]
           }}
        else
          {:ok, %{content: "What color do you prefer?"}}
        end
      end)

      workflow = %Workflow{
        name: "interactive-test",
        steps: [%Step{name: "ask", role: "interactive-agent", mode: :interactive}]
      }

      input_fn = fn _step_name, content ->
        assert content =~ "What color"
        {:ok, "blue"}
      end

      assert {:ok, result} =
               run_wf(
                 workflow,
                 %{task: "Pick a color"},
                 Map.put(ctx, :familiar_dir, familiar_dir),
                 input_fn: input_fn
               )

      assert [%{step: "ask"}] = result.steps
    end

    test "interactive step completes on signal_ready", ctx do
      stub_interactive_llm()
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["signal-agent"])

      Familiar.Providers.LLMMock
      |> stub(:chat, fn _messages, _opts ->
        # Agent calls signal_ready tool
        {:ok,
         %{
           content: "Signaling ready",
           tool_calls: [%{"name" => "signal_ready", "arguments" => %{}}]
         }}
      end)

      workflow = %Workflow{
        name: "signal-test",
        steps: [%Step{name: "work", role: "signal-agent", mode: :interactive}]
      }

      assert {:ok, result} =
               run_wf(workflow, %{task: "Do work"}, Map.put(ctx, :familiar_dir, familiar_dir))

      assert [%{step: "work"}] = result.steps
    end

    test "interactive_halted when input_fn returns halt", ctx do
      stub_interactive_llm()
      familiar_dir = tmp_dir()
      create_role_files(familiar_dir, ["halt-agent"])

      Familiar.Providers.LLMMock
      |> stub(:chat, fn _messages, _opts ->
        {:ok, %{content: "Question?"}}
      end)

      workflow = %Workflow{
        name: "halt-test",
        steps: [%Step{name: "ask", role: "halt-agent", mode: :interactive}]
      }

      input_fn = fn _step, _content -> {:halt, "user quit"} end

      assert {:error, {:interactive_halted, %{step: "ask"}}} =
               run_wf(workflow, %{task: "Ask"}, Map.put(ctx, :familiar_dir, familiar_dir),
                 input_fn: input_fn
               )
    end
  end

  defp setup_default_files do
    dir = Path.join(System.tmp_dir!(), "wf_default_#{System.unique_integer([:positive])}")
    familiar_dir = Path.join(dir, ".familiar")
    File.mkdir_p!(familiar_dir)
    DefaultFiles.install(familiar_dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    familiar_dir
  end
end
