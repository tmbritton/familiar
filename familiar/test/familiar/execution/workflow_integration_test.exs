defmodule Familiar.Execution.WorkflowIntegrationTest do
  @moduledoc """
  End-to-end integration test for the workflow pipeline.

  Validates: CLI dispatch → WorkflowRunner → AgentProcess → LLM mock →
  conversation persistence → step results. Uses real default files
  installed by DefaultFiles.install/1 and the real WorkflowRunner
  (not mocked).
  """

  use Familiar.DataCase, async: false

  import Ecto.Query
  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]
  import Mox

  alias Familiar.CLI.Main
  alias Familiar.Conversations.Conversation
  alias Familiar.Daemon.Paths
  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Knowledge.DefaultFiles

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()

    # Per-test temp directory with .familiar/ structure
    dir = Path.join(System.tmp_dir!(), "wf_integ_#{System.unique_integer([:positive])}")
    familiar_dir = Path.join(dir, ".familiar")
    File.mkdir_p!(familiar_dir)

    Application.put_env(:familiar, :project_dir, dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)

    # Install real default files (workflows, roles, skills)
    DefaultFiles.install(familiar_dir)

    # Per-test DynamicSupervisor for agent isolation
    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    # Ensure signal_ready tool is registered (prevents tool_registry_test interference)
    WorkflowRunner.register_signal_ready_tool()

    # Mock stubs — LLM returns role-based responses, handles interactive signal_ready
    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      {:ok, zero_vector()}
    end)

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-04 12:00:00Z] end)

    stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
      interactive_llm_response(messages)
    end)

    Process.flag(:trap_exit, true)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, project_dir: dir, familiar_dir: familiar_dir, supervisor: sup}
  end

  # -- Helpers --

  defp cli_deps(ctx, overrides \\ []) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end,
      workflow_fn: fn path, context, opts ->
        WorkflowRunner.run_workflow(
          path,
          context,
          Keyword.merge(opts,
            familiar_dir: ctx.familiar_dir,
            supervisor: ctx.supervisor
          )
        )
      end,
      input_fn: fn _step, _content -> {:ok, "User response"} end
    }

    Map.merge(base, Map.new(overrides))
  end

  defp interactive_llm_response(messages) do
    system = hd(messages)

    if system.content =~ "FAIL_MODE" do
      {:error, {:provider_error, %{}}}
    else
      role_name = extract_role_from_system(system.content)
      user_msgs = Enum.count(messages, &(&1.role == "user"))
      tool_msgs = Enum.count(messages, &(&1.role == "tool"))

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
  end

  defp extract_role_from_system(content) do
    case Regex.run(~r/You are a ([a-z][a-z0-9 -]+)/, content) do
      [_, name] -> String.trim(name)
      _ -> "unknown"
    end
  end

  # == AC1: Full Pipeline — CLI → WorkflowRunner → AgentProcess ==

  describe "full pipeline integration" do
    test "fam plan dispatches through real WorkflowRunner and completes", ctx do
      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, result} = Main.run({"plan", ["Plan", "user", "auth"], %{}}, deps)

      assert result.workflow == "feature-planning"
      assert length(result.steps) == 3

      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["research", "draft-spec", "review-spec"]

      for step <- result.steps do
        assert is_binary(step.output) and step.output != ""
      end
    end
  end

  # == AC2: All Three Default Workflows ==

  describe "all default workflows via CLI" do
    test "feature-implementation workflow completes with 3 steps", ctx do
      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, result} = Main.run({"do", ["Implement", "login"], %{}}, deps)

      assert result.workflow == "feature-implementation"
      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["implement", "test", "review"]
    end

    test "task-fix workflow completes with 3 steps", ctx do
      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, result} = Main.run({"fix", ["broken", "redirect"], %{}}, deps)

      assert result.workflow == "task-fix"
      step_names = Enum.map(result.steps, & &1.step)
      assert step_names == ["diagnose", "fix", "verify"]
    end
  end

  # == AC3: Context Flows Between Steps ==

  describe "context flow between steps" do
    test "later steps receive prior step output in task description", ctx do
      test_pid = self()

      # Track what each step receives as context
      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        user_msg = Enum.find(messages, &(&1.role == "user"))

        if user_msg do
          cond do
            user_msg.content =~ "Step: review" ->
              send(test_pid, {:review_context, user_msg.content})

            user_msg.content =~ "Step: test" ->
              send(test_pid, {:test_context, user_msg.content})

            true ->
              :ok
          end
        end

        interactive_llm_response(messages)
      end)

      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, _result} = Main.run({"do", ["Implement", "feature"], %{}}, deps)

      # review step should see both implement and test output (it inputs from both)
      assert_receive {:review_context, context}, 5_000
      assert context =~ "implement:"
      assert context =~ "test:"
      assert context =~ "Result from"

      # test step should see implement output (it inputs from implement)
      assert_receive {:test_context, context}, 5_000
      assert context =~ "implement:"
      assert context =~ "Result from"
    end
  end

  # == AC4: Conversation Persistence ==

  describe "conversation persistence" do
    test "each workflow step creates a persisted conversation with messages", ctx do
      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, _result} = Main.run({"fix", ["broken", "test"], %{}}, deps)

      # Each step should have created a conversation
      conversations =
        from(c in Conversation,
          where: c.scope == "agent",
          order_by: [asc: c.inserted_at]
        )
        |> Repo.all()

      # task-fix has 3 steps → 3 conversations
      assert length(conversations) == 3

      # Each conversation should have messages
      for conv <- conversations do
        {:ok, messages} = Familiar.Conversations.messages(conv.id)

        assert length(messages) >= 2,
               "conversation #{conv.id} should have at least system + user messages"

        roles = Enum.map(messages, & &1.role)
        assert "system" in roles
        assert "user" in roles
      end
    end

    test "planning workflow creates conversations with planning scope", ctx do
      Paths.ensure_familiar_dir!()
      deps = cli_deps(ctx)

      assert {:ok, _result} = Main.run({"plan", ["Plan", "feature"], %{}}, deps)

      planning_convs =
        from(c in Conversation, where: c.scope == "planning")
        |> Repo.all()

      assert length(planning_convs) == 3
    end
  end

  # == AC5: Error Propagation ==

  describe "error propagation" do
    test "LLM failure in a step propagates to CLI as step_failed", ctx do
      Paths.ensure_familiar_dir!()

      # Overwrite the default coder role with one that triggers FAIL_MODE
      coder_path = Path.join([ctx.familiar_dir, "roles", "coder.md"])

      File.write!(coder_path, """
      ---
      name: coder
      description: A coder that fails
      skills: []
      ---

      FAIL_MODE You are a coder that will fail.
      """)

      deps = cli_deps(ctx)

      # feature-implementation uses the coder role for "implement" step
      assert {:error, {:step_failed, %{step: "implement"}}} =
               Main.run({"do", ["Implement", "something"], %{}}, deps)
    end

    test "workflow with missing role file returns start_failed error", ctx do
      Paths.ensure_familiar_dir!()

      # Write a workflow that references a non-existent role
      workflow_path = Path.join([ctx.familiar_dir, "workflows", "bad-workflow.md"])

      File.write!(workflow_path, """
      ---
      name: bad-workflow
      steps:
        - name: step1
          role: nonexistent-role
      ---

      A workflow with a missing role.
      """)

      result =
        WorkflowRunner.run_workflow(
          workflow_path,
          %{task: "test"},
          familiar_dir: ctx.familiar_dir,
          supervisor: ctx.supervisor
        )

      assert {:error, {:start_failed, %{step: "step1"}}} = result
    end
  end

  # == AC6: Workflow File Validation ==

  describe "workflow file validation" do
    test "malformed YAML returns clear error", ctx do
      path = Path.join(ctx.project_dir, "bad.md")
      File.write!(path, "no frontmatter here at all")

      assert {:error, {:malformed_yaml, _msg}} = WorkflowRunner.parse(path)
    end

    test "workflow missing name field returns clear error", ctx do
      path = Path.join(ctx.project_dir, "noname.md")

      File.write!(path, """
      ---
      description: No name field
      steps:
        - name: s1
          role: analyst
      ---
      Body.
      """)

      assert {:error, {:invalid_workflow, "missing required field: name"}} =
               WorkflowRunner.parse(path)
    end

    test "workflow with step missing role returns clear error", ctx do
      path = Path.join(ctx.project_dir, "norole.md")

      File.write!(path, """
      ---
      name: norole-wf
      steps:
        - name: s1
      ---
      Body.
      """)

      assert {:error, {:invalid_step, _}} = WorkflowRunner.parse(path)
    end

    test "nonexistent workflow file returns file_error" do
      assert {:error, {:file_error, %{path: "/nonexistent.md", reason: :enoent}}} =
               WorkflowRunner.parse("/nonexistent.md")
    end
  end
end
