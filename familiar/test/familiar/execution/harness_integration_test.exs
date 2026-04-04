defmodule Familiar.Execution.HarnessIntegrationTest do
  @moduledoc """
  End-to-end integration test validating the complete agent harness.

  Golden path: load extensions → register tools/hooks → start workflow →
  spawn AgentProcess → tool-call loop with mocked LLM → file writes via
  transaction module → safety extension vetoes out-of-scope write →
  knowledge extension captures results → workflow completes.

  Uses real SQLite (via Ecto sandbox) with mocked LLM/Shell/FileSystem.
  """

  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Execution.ExtensionLoader
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Execution.WorkflowRunner
  alias Familiar.Execution.WorkflowRunner.Step
  alias Familiar.Execution.WorkflowRunner.Workflow
  alias Familiar.Files
  alias Familiar.Files.Transaction

  @moduletag :integration

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()

    # Per-test temp directory for project + familiar_dir
    dir = Path.join(System.tmp_dir!(), "harness_integ_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    familiar_dir = Path.join(dir, ".familiar")
    File.mkdir_p!(familiar_dir)

    Application.put_env(:familiar, :project_dir, dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)

    # Per-test DynamicSupervisor for agent isolation
    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    # Default mock stubs
    stub(Familiar.Knowledge.EmbedderMock, :embed, fn _text ->
      {:ok, List.duplicate(0.0, 768)}
    end)

    stub(Familiar.System.FileSystemMock, :stat, fn _path ->
      {:ok, %{mtime: ~U[2020-01-01 00:00:00Z], size: 100}}
    end)

    stub(Familiar.System.ClockMock, :now, fn -> ~U[2026-04-04 12:00:00Z] end)

    # Default shell stub (git ls-files returns not-tracked)
    stub(Familiar.System.ShellMock, :cmd, fn _cmd, _args, _opts ->
      {:ok, %{output: "", exit_code: 1}}
    end)

    Process.flag(:trap_exit, true)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, project_dir: dir, familiar_dir: familiar_dir, supervisor: sup}
  end

  # -- Helpers --

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

  defp load_extensions!(project_dir) do
    Code.ensure_loaded!(Familiar.Extensions.Safety)
    Code.ensure_loaded!(Familiar.Extensions.KnowledgeStore)

    {:ok, result} =
      ExtensionLoader.load_extensions(
        [Familiar.Extensions.Safety, Familiar.Extensions.KnowledgeStore],
        project_dir: project_dir
      )

    # Verify extensions actually loaded
    assert "safety" in result.loaded
    assert "knowledge-store" in result.loaded

    # Register extension tools
    for {name, fun, desc, ext} <- result.tools do
      ToolRegistry.register(name, fun, desc, ext)
    end

    result
  end

  defp build_workflow(steps) do
    %Workflow{
      name: "test-workflow",
      description: "Integration test workflow",
      steps:
        Enum.map(steps, fn {name, role} ->
          %Step{name: name, role: role}
        end)
    }
  end

  # -- Role-based LLM response helpers --

  defp role_from_system(content) do
    case Regex.run(~r/You are a ([a-z][a-z0-9-]*)/, content) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  # == AC1: Golden Path — Extension Loading Through Workflow Completion ==

  describe "golden path" do
    test "workflow with tool calls completes end-to-end", ctx do
      create_role_files(ctx.familiar_dir, ["analyst", "coder"])
      load_extensions!(ctx.project_dir)

      # Per-role call counters to avoid cross-role ordering fragility
      coder_calls = :counters.new(1, [:atomics])

      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        role = role_from_system(hd(messages).content)

        case role do
          "analyst" ->
            {:ok, %{content: "Analysis complete: implement auth module", tool_calls: []}}

          "coder" ->
            count = :counters.get(coder_calls, 1)
            :counters.add(coder_calls, 1, 1)

            if count == 0 do
              {:ok,
               %{
                 content: nil,
                 tool_calls: [
                   %{
                     "name" => "write_file",
                     "arguments" => %{
                       "path" => Path.join(ctx.project_dir, "lib/auth.ex"),
                       "content" => "defmodule Auth do\nend"
                     }
                   }
                 ]
               }}
            else
              {:ok, %{content: "Implementation complete: wrote auth.ex", tool_calls: []}}
            end

          _ ->
            {:ok, %{content: "Done", tool_calls: []}}
        end
      end)

      # FileSystem mock: allow writes within project dir
      stub(Familiar.System.FileSystemMock, :read, fn _path ->
        {:error, {:file_error, %{reason: :enoent}}}
      end)

      stub(Familiar.System.FileSystemMock, :write, fn _path, _content -> :ok end)

      workflow = build_workflow([{"analyze", "analyst"}, {"implement", "coder"}])

      assert {:ok, results} =
               WorkflowRunner.run_workflow_parsed(workflow, %{task: "Build auth"},
                 supervisor: ctx.supervisor,
                 familiar_dir: ctx.familiar_dir,
                 timeout_ms: 10_000
               )

      # Verify workflow completed with both step results
      step_names = Enum.map(results.steps, & &1.step)
      assert "analyze" in step_names
      assert "implement" in step_names

      # Verify analyst output propagated
      analyze_result = Enum.find(results.steps, &(&1.step == "analyze"))
      assert analyze_result.output =~ "Analysis complete"

      # Verify file write went through transaction module (AgentProcess injects task_id)
      txns = Repo.all(Transaction)
      assert txns != []
      assert Enum.any?(txns, &(&1.status == "completed"))
    end
  end

  # == AC2: Safety Extension Vetoes Out-of-Scope Write ==

  describe "safety veto" do
    test "blocks write outside project directory", ctx do
      create_role_files(ctx.familiar_dir, ["rogue"])
      load_extensions!(ctx.project_dir)

      veto_calls = :counters.new(1, [:atomics])

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        count = :counters.get(veto_calls, 1)
        :counters.add(veto_calls, 1, 1)

        if count == 0 do
          {:ok,
           %{
             content: nil,
             tool_calls: [
               %{
                 "name" => "write_file",
                 "arguments" => %{
                   "path" => "/etc/evil.conf",
                   "content" => "malicious"
                 }
               }
             ]
           }}
        else
          {:ok, %{content: "Understood, write was blocked", tool_calls: []}}
        end
      end)

      workflow = build_workflow([{"exploit", "rogue"}])

      assert {:ok, results} =
               WorkflowRunner.run_workflow_parsed(workflow, %{task: "Try bad write"},
                 supervisor: ctx.supervisor,
                 familiar_dir: ctx.familiar_dir,
                 timeout_ms: 10_000
               )

      # Agent completed — veto was returned as tool result, not a crash
      exploit_result = Enum.find(results.steps, &(&1.step == "exploit"))
      assert exploit_result.output =~ "blocked"

      # No file transaction created for the vetoed write
      assert Repo.all(Transaction) == []
    end
  end

  # == AC3: File Transaction Integration ==

  describe "file transaction integration" do
    test "writes create transaction records when task_id present", ctx do
      stub(Familiar.System.FileSystemMock, :read, fn _path ->
        {:error, {:file_error, %{reason: :enoent}}}
      end)

      stub(Familiar.System.FileSystemMock, :write, fn _path, _content -> :ok end)

      path = Path.join(ctx.project_dir, "lib/new.ex")
      assert {:ok, txn} = Files.write(path, "defmodule New do\nend", "task_42")
      assert txn.status == "completed"
      assert txn.file_path == path

      # Verify via fresh DB read
      [db_txn] = Repo.all(Transaction)
      assert db_txn.status == "completed"

      # claimed_files is empty for completed transactions
      assert Files.claimed_files() == %{}
    end
  end

  # == AC4: Agent Crash Recovery ==

  describe "agent crash" do
    test "workflow reports failure with step name when agent's LLM errors", ctx do
      create_role_files(ctx.familiar_dir, ["fail-agent"])

      stub(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_error, %{message: "service unavailable"}}}
      end)

      workflow = build_workflow([{"fail-step", "fail-agent"}])

      assert {:error, {:step_failed, %{step: "fail-step", reason: reason}}} =
               WorkflowRunner.run_workflow_parsed(workflow, %{task: "This will fail"},
                 supervisor: ctx.supervisor,
                 familiar_dir: ctx.familiar_dir,
                 timeout_ms: 10_000
               )

      assert reason != nil
    end

    test "system remains stable after agent crash — can run another workflow", ctx do
      create_role_files(ctx.familiar_dir, ["crash-agent", "good-agent"])

      stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        system = hd(messages).content

        if system =~ "crash-agent" do
          {:error, {:provider_error, %{}}}
        else
          {:ok, %{content: "Success from good-agent", tool_calls: []}}
        end
      end)

      # First workflow fails
      workflow1 = build_workflow([{"crash-step", "crash-agent"}])

      assert {:error, _} =
               WorkflowRunner.run_workflow_parsed(workflow1, %{task: "Crash"},
                 supervisor: ctx.supervisor,
                 familiar_dir: ctx.familiar_dir,
                 timeout_ms: 10_000
               )

      # Second workflow succeeds — system is stable
      workflow2 = build_workflow([{"good-step", "good-agent"}])

      assert {:ok, results} =
               WorkflowRunner.run_workflow_parsed(workflow2, %{task: "Recover"},
                 supervisor: ctx.supervisor,
                 familiar_dir: ctx.familiar_dir,
                 timeout_ms: 10_000
               )

      assert Enum.any?(results.steps, &(&1.step == "good-step"))
    end
  end

  # == AC5: Conflict Detection Path ==

  describe "conflict detection" do
    test "detects external modification and creates .fam-pending", ctx do
      original = "original content"
      modified = "user edited this"
      agent_content = "agent version"

      read_count = :counters.new(1, [:atomics])

      stub(Familiar.System.FileSystemMock, :read, fn _path ->
        count = :counters.get(read_count, 1)
        :counters.add(read_count, 1, 1)
        if count == 0, do: {:ok, original}, else: {:ok, modified}
      end)

      expect(Familiar.System.FileSystemMock, :write, fn path, content ->
        assert String.ends_with?(path, ".fam-pending")
        assert content == agent_content
        :ok
      end)

      path = Path.join(ctx.project_dir, "lib/contested.ex")

      assert {:error, {:conflict, %{path: ^path}}} =
               Files.write(path, agent_content, "task_conflict")

      # Transaction marked as conflict
      [txn] = Repo.all(Transaction)
      assert txn.status == "conflict"

      # pending_conflicts returns the record
      conflicts = Files.pending_conflicts()
      assert [conflict] = conflicts
      assert conflict.file_path == path
    end
  end
end
