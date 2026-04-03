defmodule Familiar.Execution.AgentProcessTest do
  use Familiar.DataCase, async: false

  import Mox

  alias Familiar.Conversations
  alias Familiar.Execution.AgentProcess
  alias Familiar.Execution.AgentSupervisor
  alias Familiar.Execution.ToolRegistry
  alias Familiar.Providers.LLMMock

  @moduletag :tmp_dir

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    # Create role and skill fixture files
    roles_dir = Path.join(tmp_dir, "roles")
    skills_dir = Path.join(tmp_dir, "skills")
    File.mkdir_p!(roles_dir)
    File.mkdir_p!(skills_dir)

    File.write!(Path.join(roles_dir, "test-agent.md"), """
    ---
    name: test-agent
    description: A test agent
    model: test-model
    lifecycle: ephemeral
    skills:
      - test-skill
    ---
    You are a test agent. Follow instructions precisely.
    """)

    File.write!(Path.join(skills_dir, "test-skill.md"), """
    ---
    name: test-skill
    description: Test skill
    tools:
      - read_file
    ---
    Use tools when needed.
    """)

    File.write!(Path.join(roles_dir, "no-skills.md"), """
    ---
    name: no-skills
    description: Agent without skills
    model: test-model
    lifecycle: ephemeral
    skills: []
    ---
    You are a simple agent.
    """)

    {:ok, familiar_dir: tmp_dir}
  end

  describe "init/1 with valid role" do
    test "starts agent, loads role, creates conversation", %{familiar_dir: dir} do
      # LLM returns immediately with no tool calls
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Done.", tool_calls: [], usage: %{}}}
      end)

      parent = self()

      {:ok, pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "do something",
          parent: parent,
          familiar_dir: dir
        )

      # Agent should complete and notify parent
      assert_receive {:agent_done, agent_id, {:ok, "Done."}}, 5_000
      assert is_binary(agent_id)
      assert String.starts_with?(agent_id, "agent_")

      # Process should have stopped — wait briefly for shutdown
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end

    test "creates conversation with scope 'agent'", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "OK", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "test task",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _id, {:ok, _}}, 5_000

      # Check that a conversation was created
      import Ecto.Query

      convs =
        Familiar.Repo.all(
          from(c in Familiar.Conversations.Conversation,
            where: c.scope == "agent",
            order_by: [desc: c.inserted_at],
            limit: 1
          )
        )

      assert length(convs) == 1
      assert convs |> hd() |> Map.get(:description) =~ "test-agent"
    end
  end

  describe "init/1 with invalid role" do
    test "returns error for nonexistent role", %{familiar_dir: dir} do
      Process.flag(:trap_exit, true)

      result =
        AgentProcess.start_link(
          role: "nonexistent",
          task: "do something",
          familiar_dir: dir
        )

      assert {:error, {:role_not_found, _}} = result
    end
  end

  describe "tool call loop — no tool calls" do
    test "completes immediately when LLM returns no tool calls", %{familiar_dir: dir} do
      test_pid = self()

      stub(LLMMock, :chat, fn messages, _opts ->
        # Verify message structure
        send(test_pid, {:messages_received, messages})
        {:ok, %{content: "All done.", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "simple task",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:messages_received, messages}, 5_000
      assert [%{role: "system"}, %{role: "user"} | _] = messages

      assert_receive {:agent_done, _id, {:ok, "All done."}}, 5_000
    end

    test "system prompt includes role prompt and skill instructions", %{familiar_dir: dir} do
      test_pid = self()

      stub(LLMMock, :chat, fn messages, _opts ->
        send(test_pid, {:messages_received, messages})
        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "check prompts",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:messages_received, messages}, 5_000
      system_msg = Enum.find(messages, &(&1.role == "system"))
      assert system_msg.content =~ "You are a test agent"
      assert system_msg.content =~ "Use tools when needed"

      assert_receive {:agent_done, _, {:ok, _}}, 5_000
    end

    test "passes model from role to LLM", %{familiar_dir: dir} do
      test_pid = self()

      stub(LLMMock, :chat, fn _messages, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        {:ok, %{content: "OK", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "check model",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:model_used, "test-model"}, 5_000
      assert_receive {:agent_done, _, {:ok, _}}, 5_000
    end
  end

  describe "tool call loop — with tool calls" do
    test "dispatches tools and loops until done", %{familiar_dir: dir} do
      # Register a test tool
      test_tool_name = :"test_tool_#{System.unique_integer([:positive])}"

      ToolRegistry.register(
        test_tool_name,
        fn args, _ctx -> {:ok, %{result: "read #{args[:path]}"}} end,
        "Test tool",
        "test"
      )

      tool_name_str = Atom.to_string(test_tool_name)
      call_count = :counters.new(1, [:atomics])

      stub(LLMMock, :chat, fn _messages, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          # First call: return tool calls
          {:ok,
           %{
             content: "I'll read the file.",
             tool_calls: [
               %{
                 "function" => %{
                   "name" => tool_name_str,
                   "arguments" => %{"path" => "lib/foo.ex"}
                 }
               }
             ],
             usage: %{}
           }}
        else
          # Second call: no more tool calls
          {:ok, %{content: "Done reading file.", tool_calls: [], usage: %{}}}
        end
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "read a file",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _id, {:ok, "Done reading file."}}, 5_000
    end

    test "tool dispatch passes correct context", %{familiar_dir: dir} do
      test_pid = self()
      tool_name = :"ctx_tool_#{System.unique_integer([:positive])}"

      ToolRegistry.register(
        tool_name,
        fn _args, ctx ->
          send(test_pid, {:tool_context, ctx})
          {:ok, %{done: true}}
        end,
        "Context test tool",
        "test"
      )

      tool_name_str = Atom.to_string(tool_name)
      call_count = :counters.new(1, [:atomics])

      stub(LLMMock, :chat, fn _messages, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:ok,
           %{
             content: "",
             tool_calls: [
               %{"function" => %{"name" => tool_name_str, "arguments" => %{}}}
             ],
             usage: %{}
           }}
        else
          {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
        end
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "test context",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:tool_context, ctx}, 5_000
      assert is_binary(ctx.agent_id)
      assert ctx.role == "test-agent"
      assert is_integer(ctx.conversation_id)

      assert_receive {:agent_done, _, {:ok, _}}, 5_000
    end

    test "vetoed tool call is formatted as error message to LLM", %{familiar_dir: dir} do
      tool_name = :"veto_tool_#{System.unique_integer([:positive])}"

      ToolRegistry.register(
        tool_name,
        fn _args, _ctx -> {:ok, %{}} end,
        "Will be vetoed",
        "test"
      )

      # Register a veto alter hook
      Familiar.Hooks.register_alter_hook(
        :before_tool_call,
        fn payload, _ctx ->
          if payload.tool == tool_name do
            {:halt, "operation not allowed"}
          else
            {:ok, payload}
          end
        end,
        1,
        "test-safety"
      )

      tool_name_str = Atom.to_string(tool_name)
      call_count = :counters.new(1, [:atomics])

      stub(LLMMock, :chat, fn messages, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:ok,
           %{
             content: "",
             tool_calls: [
               %{"function" => %{"name" => tool_name_str, "arguments" => %{}}}
             ],
             usage: %{}
           }}
        else
          # Verify the veto message was passed back
          tool_msgs = Enum.filter(messages, &(&1.role == "tool"))
          assert tool_msgs != []
          last_tool = List.last(tool_msgs)
          assert last_tool.content =~ "vetoed"

          {:ok, %{content: "Understood, operation vetoed.", tool_calls: [], usage: %{}}}
        end
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "try vetoed operation",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _id, {:ok, "Understood, operation vetoed."}}, 5_000
    end
  end

  describe "safety limits" do
    test "stops when max tool calls exceeded", %{familiar_dir: dir} do
      tool_name = :"limit_tool_#{System.unique_integer([:positive])}"

      ToolRegistry.register(
        tool_name,
        fn _args, _ctx -> {:ok, %{ok: true}} end,
        "Limit test",
        "test"
      )

      tool_name_str = Atom.to_string(tool_name)

      # Always return tool calls — never finish
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content: "",
           tool_calls: [
             %{"function" => %{"name" => tool_name_str, "arguments" => %{}}}
           ],
           usage: %{}
         }}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "infinite loop",
          parent: self(),
          familiar_dir: dir,
          max_tool_calls: 3
        )

      assert_receive {:agent_done, _id, {:error, {:max_tool_calls_exceeded, count}}}, 10_000
      assert count >= 3
    end

    test "stops on task timeout", %{familiar_dir: dir} do
      # LLM blocks for a long time
      stub(LLMMock, :chat, fn _messages, _opts ->
        Process.sleep(5_000)
        {:ok, %{content: "late", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "slow task",
          parent: self(),
          familiar_dir: dir,
          task_timeout_ms: 100
        )

      assert_receive {:agent_done, _id, {:error, {:timeout, _elapsed}}}, 5_000
    end
  end

  describe "completion and status reporting" do
    test "parent receives {:agent_done, id, {:ok, result}}", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Result content", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "report back",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, agent_id, {:ok, "Result content"}}, 5_000
      assert String.starts_with?(agent_id, "agent_")
    end

    test "no parent means no notification sent", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "no parent",
          familiar_dir: dir
        )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      refute_received {:agent_done, _, _}
    end

    test "LLM error results in error completion", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_error, %{message: "rate limited"}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "will fail",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _id, {:error, {:llm_error, _}}}, 5_000
    end

    test "conversation status updated to completed on success", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "check conv status",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _, {:ok, _}}, 5_000

      # Give a moment for async conversation update
      Process.sleep(50)

      import Ecto.Query

      conv =
        Familiar.Repo.one(
          from(c in Familiar.Conversations.Conversation,
            where: c.scope == "agent",
            order_by: [desc: c.inserted_at],
            limit: 1
          )
        )

      assert conv.status == "completed"
    end

    test "conversation status updated to abandoned on error", %{familiar_dir: dir} do
      stub(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_error, %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "will fail",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _, {:error, _}}, 5_000

      Process.sleep(50)

      import Ecto.Query

      conv =
        Familiar.Repo.one(
          from(c in Familiar.Conversations.Conversation,
            where: c.scope == "agent",
            order_by: [desc: c.inserted_at],
            limit: 1
          )
        )

      assert conv.status == "abandoned"
    end
  end

  describe "lifecycle events" do
    test "broadcasts on_agent_start and on_agent_complete", %{familiar_dir: dir} do
      # Subscribe to hooks events
      topic_start = Familiar.Activity.topic("hooks:on_agent_start")
      topic_complete = Familiar.Activity.topic("hooks:on_agent_complete")
      Phoenix.PubSub.subscribe(Familiar.PubSub, topic_start)
      Phoenix.PubSub.subscribe(Familiar.PubSub, topic_complete)

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "events test",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _, {:ok, _}}, 5_000

      assert_receive {:hook_event, :on_agent_start,
                      %{agent_id: _, role: "test-agent", task: "events test"}},
                     1_000

      assert_receive {:hook_event, :on_agent_complete,
                      %{agent_id: _, role: "test-agent", result: "Done"}},
                     1_000
    end

    test "broadcasts on_agent_error on failure", %{familiar_dir: dir} do
      topic = Familiar.Activity.topic("hooks:on_agent_error")
      Phoenix.PubSub.subscribe(Familiar.PubSub, topic)

      stub(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_error, %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "error events",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _, {:error, _}}, 5_000

      assert_receive {:hook_event, :on_agent_error, %{agent_id: _, role: "test-agent", error: _}},
                     1_000
    end
  end

  describe "conversation persistence" do
    test "messages are persisted to database", %{familiar_dir: dir} do
      tool_name = :"persist_tool_#{System.unique_integer([:positive])}"

      ToolRegistry.register(
        tool_name,
        fn _args, _ctx -> {:ok, %{data: "file contents"}} end,
        "Persist test",
        "test"
      )

      tool_name_str = Atom.to_string(tool_name)
      call_count = :counters.new(1, [:atomics])

      stub(LLMMock, :chat, fn _messages, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:ok,
           %{
             content: "Reading file...",
             tool_calls: [
               %{"function" => %{"name" => tool_name_str, "arguments" => %{"path" => "foo.ex"}}}
             ],
             usage: %{}
           }}
        else
          {:ok, %{content: "Final answer.", tool_calls: [], usage: %{}}}
        end
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "persistence test",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:agent_done, _, {:ok, "Final answer."}}, 5_000

      Process.sleep(50)

      import Ecto.Query

      conv =
        Familiar.Repo.one(
          from(c in Familiar.Conversations.Conversation,
            where: c.scope == "agent",
            order_by: [desc: c.inserted_at],
            limit: 1
          )
        )

      {:ok, messages} = Conversations.messages(conv.id)

      # Should have: assistant (with tool calls) + tool result + assistant (final)
      roles = Enum.map(messages, & &1.role)
      assert "assistant" in roles
      assert "tool" in roles
      assert length(messages) >= 3
    end
  end

  describe "status/1" do
    test "returns current agent state while LLM is processing", %{familiar_dir: dir} do
      test_pid = self()
      gate = :persistent_term.put({__MODULE__, :status_gate}, :wait)

      # LLM blocks until we signal it
      stub(LLMMock, :chat, fn _messages, _opts ->
        send(test_pid, {:llm_called, self()})

        # Wait for signal from test
        receive do
          :continue -> :ok
        after
          10_000 -> :ok
        end

        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, pid} =
        AgentProcess.start_link(
          role: "test-agent",
          task: "status test",
          parent: self(),
          familiar_dir: dir
        )

      # Wait for LLM to be called (running in Task, GenServer is free)
      assert_receive {:llm_called, llm_pid}, 5_000

      # GenServer is responsive now — query status during LLM call
      {:ok, status} = AgentProcess.status(pid)
      assert status.role == "test-agent"
      assert status.status == :running
      assert status.tool_calls == 0
      assert is_integer(status.elapsed_ms)
      assert String.starts_with?(status.agent_id, "agent_")

      # Let the LLM finish
      send(llm_pid, :continue)

      assert_receive {:agent_done, _, {:ok, "Done"}}, 5_000

      _ = gate
    end
  end

  describe "list_agents/0" do
    test "returns running agents", %{familiar_dir: dir} do
      test_pid = self()

      stub(LLMMock, :chat, fn _messages, _opts ->
        send(test_pid, {:llm_called, self()})

        receive do
          :continue -> :ok
        after
          10_000 -> :ok
        end

        {:ok, %{content: "Done", tool_calls: [], usage: %{}}}
      end)

      {:ok, pid} =
        AgentSupervisor.start_agent(
          role: "test-agent",
          task: "list test",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:llm_called, llm_pid}, 5_000

      agents = AgentProcess.list_agents()
      assert agents != []
      assert Enum.any?(agents, fn {p, _id} -> p == pid end)

      # Let agent finish
      send(llm_pid, :continue)
      assert_receive {:agent_done, _, {:ok, _}}, 5_000
    end
  end

  describe "agent without skills" do
    test "works with no-skills role", %{familiar_dir: dir} do
      test_pid = self()

      stub(LLMMock, :chat, fn messages, _opts ->
        send(test_pid, {:messages_received, messages})
        {:ok, %{content: "No skills needed.", tool_calls: [], usage: %{}}}
      end)

      {:ok, _pid} =
        AgentProcess.start_link(
          role: "no-skills",
          task: "simple task",
          parent: self(),
          familiar_dir: dir
        )

      assert_receive {:messages_received, messages}, 5_000
      system_msg = Enum.find(messages, &(&1.role == "system"))
      assert system_msg.content == "You are a simple agent."

      assert_receive {:agent_done, _, {:ok, "No skills needed."}}, 5_000
    end
  end
end
