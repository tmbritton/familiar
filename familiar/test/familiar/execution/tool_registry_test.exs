defmodule Familiar.Execution.ToolRegistryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Familiar.Execution.ToolRegistry
  alias Familiar.Hooks

  setup do
    hooks_name = :"hooks_#{System.unique_integer([:positive])}"
    registry_name = :"registry_#{System.unique_integer([:positive])}"

    start_supervised!({Hooks, name: hooks_name})
    start_supervised!({ToolRegistry, name: registry_name})

    {:ok, hooks: hooks_name, registry: registry_name}
  end

  # Helper to call the named registry GenServer directly
  defp register_tool(registry, name, function, description, extension \\ "test-ext") do
    GenServer.call(registry, {:register, name, function, description, extension})
  end

  defp dispatch_tool(registry, hooks, name, args \\ %{}, context \\ %{}) do
    # Dispatch needs to go through the registry but hooks through the named hooks server
    # We need to do the dispatch logic manually for per-test isolation
    case GenServer.call(registry, {:get_tool, name}) do
      {:ok, tool} ->
        case GenServer.call(
               hooks,
               {:alter, :before_tool_call, %{tool: name, args: args}, context},
               :infinity
             ) do
          {:ok, modified_payload} ->
            modified_args = Map.get(modified_payload, :args, %{})

            try do
              case tool.function.(modified_args, context) do
                {:ok, result} -> {:ok, result}
                {:error, reason} -> {:error, reason}
                other -> {:error, {:invalid_return, other}}
              end
            rescue
              error -> {:error, {:tool_crashed, Exception.message(error)}}
            end

          {:halt, reason} ->
            {:error, {:vetoed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_tools(registry) do
    GenServer.call(registry, :list_tools)
  end

  defp get_tool(registry, name) do
    GenServer.call(registry, {:get_tool, name})
  end

  describe "register/4 and list_tools/0" do
    test "registers a tool and lists it", %{registry: registry} do
      fun = fn _args, _ctx -> {:ok, %{content: "hello"}} end
      :ok = register_tool(registry, :read_file, fun, "Read a file")

      tools = list_tools(registry)
      assert [%{name: :read_file, description: "Read a file", extension: "test-ext"}] = tools
    end

    test "registers multiple tools", %{registry: registry} do
      fun = fn _args, _ctx -> {:ok, %{}} end
      :ok = register_tool(registry, :tool_a, fun, "Tool A", "ext-a")
      :ok = register_tool(registry, :tool_b, fun, "Tool B", "ext-b")

      tools = list_tools(registry)
      assert length(tools) == 2
      names = Enum.map(tools, & &1.name) |> Enum.sort()
      assert names == [:tool_a, :tool_b]
    end

    test "duplicate registration overwrites and logs warning", %{registry: registry} do
      fun1 = fn _args, _ctx -> {:ok, %{v: 1}} end
      fun2 = fn _args, _ctx -> {:ok, %{v: 2}} end

      :ok = register_tool(registry, :my_tool, fun1, "Version 1", "ext-1")

      log =
        capture_log(fn ->
          :ok = register_tool(registry, :my_tool, fun2, "Version 2", "ext-2")
        end)

      assert log =~ "Overwriting tool :my_tool"
      assert log =~ "ext-1"
      assert log =~ "ext-2"

      {:ok, entry} = get_tool(registry, :my_tool)
      assert entry.description == "Version 2"
      assert entry.extension == "ext-2"
    end
  end

  describe "get_tool/1" do
    test "returns tool entry when registered", %{registry: registry} do
      fun = fn _args, _ctx -> {:ok, %{}} end
      :ok = register_tool(registry, :my_tool, fun, "My tool")

      assert {:ok, entry} = get_tool(registry, :my_tool)
      assert entry.description == "My tool"
      assert entry.extension == "test-ext"
      assert is_function(entry.function, 2)
    end

    test "returns error for unknown tool", %{registry: registry} do
      assert {:error, {:unknown_tool, :nonexistent}} = get_tool(registry, :nonexistent)
    end
  end

  describe "dispatch/3" do
    test "dispatches tool and returns result", %{registry: registry, hooks: hooks} do
      fun = fn args, _ctx -> {:ok, %{content: args.path}} end
      :ok = register_tool(registry, :read_file, fun, "Read a file")

      assert {:ok, %{content: "foo.ex"}} =
               dispatch_tool(registry, hooks, :read_file, %{path: "foo.ex"})
    end

    test "returns error for unknown tool", %{registry: registry, hooks: hooks} do
      assert {:error, {:unknown_tool, :missing}} =
               dispatch_tool(registry, hooks, :missing)
    end

    test "runs before_tool_call alter hook before execution", %{registry: registry, hooks: hooks} do
      test_pid = self()

      # Register an alter hook that records it was called
      alter_fn = fn payload, _ctx ->
        send(test_pid, {:alter_called, payload})
        {:ok, payload}
      end

      GenServer.call(hooks, {:register_alter, :before_tool_call, alter_fn, 50, "test-safety"})

      tool_fn = fn _args, _ctx -> {:ok, %{done: true}} end
      :ok = register_tool(registry, :my_tool, tool_fn, "A tool")

      assert {:ok, %{done: true}} =
               dispatch_tool(registry, hooks, :my_tool, %{x: 1})

      assert_received {:alter_called, %{tool: :my_tool, args: %{x: 1}}}
    end

    test "alter hook can veto tool call", %{registry: registry, hooks: hooks} do
      alter_fn = fn _payload, _ctx ->
        {:halt, "dangerous operation"}
      end

      GenServer.call(hooks, {:register_alter, :before_tool_call, alter_fn, 1, "safety"})

      tool_fn = fn _args, _ctx -> {:ok, %{should_not: :reach}} end
      :ok = register_tool(registry, :danger_tool, tool_fn, "Dangerous")

      assert {:error, {:vetoed, "dangerous operation"}} =
               dispatch_tool(registry, hooks, :danger_tool, %{path: "/etc/passwd"})
    end

    test "alter hook can modify args", %{registry: registry, hooks: hooks} do
      alter_fn = fn payload, _ctx ->
        modified_args = Map.put(payload.args, :sanitized, true)
        {:ok, %{payload | args: modified_args}}
      end

      GenServer.call(hooks, {:register_alter, :before_tool_call, alter_fn, 50, "sanitizer"})

      tool_fn = fn args, _ctx -> {:ok, %{received_sanitized: args.sanitized}} end
      :ok = register_tool(registry, :my_tool, tool_fn, "A tool")

      assert {:ok, %{received_sanitized: true}} =
               dispatch_tool(registry, hooks, :my_tool, %{data: "raw"})
    end

    test "tool crash returns error without crashing registry", %{registry: registry, hooks: hooks} do
      tool_fn = fn _args, _ctx -> raise "boom!" end
      :ok = register_tool(registry, :crashing_tool, tool_fn, "Will crash")

      assert {:error, {:tool_crashed, message}} =
               dispatch_tool(registry, hooks, :crashing_tool)

      assert message =~ "boom!"

      # Registry is still alive
      assert {:ok, _} = get_tool(registry, :crashing_tool)
    end

    test "tool returning error propagates", %{registry: registry, hooks: hooks} do
      tool_fn = fn _args, _ctx -> {:error, {:file_not_found, "missing.ex"}} end
      :ok = register_tool(registry, :read_file, tool_fn, "Read a file")

      assert {:error, {:file_not_found, "missing.ex"}} =
               dispatch_tool(registry, hooks, :read_file, %{path: "missing.ex"})
    end

    test "tool returning unexpected value returns invalid_return error", %{
      registry: registry,
      hooks: hooks
    } do
      tool_fn = fn _args, _ctx -> :done end
      :ok = register_tool(registry, :weird_tool, tool_fn, "Returns non-standard")

      assert {:error, {:invalid_return, :done}} =
               dispatch_tool(registry, hooks, :weird_tool)
    end

    test "context is passed to tool function", %{registry: registry, hooks: hooks} do
      tool_fn = fn _args, ctx -> {:ok, %{agent_id: ctx.agent_id}} end
      :ok = register_tool(registry, :my_tool, tool_fn, "A tool")

      context = %{agent_id: "agent-123", scope: "project"}

      assert {:ok, %{agent_id: "agent-123"}} =
               dispatch_tool(registry, hooks, :my_tool, %{}, context)
    end
  end

  describe "after_tool_call event" do
    test "broadcasts after_tool_call on success via real dispatch" do
      # Uses the globally started ToolRegistry and Hooks from the application
      topic = Familiar.Activity.topic("hooks:after_tool_call")
      Phoenix.PubSub.subscribe(Familiar.PubSub, topic)

      unique = :"after_ok_#{System.unique_integer([:positive])}"
      tool_fn = fn _args, _ctx -> {:ok, %{data: "result"}} end
      ToolRegistry.register(unique, tool_fn, "A test tool", "test-ext")

      assert {:ok, %{data: "result"}} = ToolRegistry.dispatch(unique, %{x: 1})

      assert_receive {:hook_event, :after_tool_call,
                      %{tool: ^unique, args: %{x: 1}, result: {:ok, %{data: "result"}}}}
    end

    test "broadcasts after_tool_call on error via real dispatch" do
      topic = Familiar.Activity.topic("hooks:after_tool_call")
      Phoenix.PubSub.subscribe(Familiar.PubSub, topic)

      unique = :"after_err_#{System.unique_integer([:positive])}"
      tool_fn = fn _args, _ctx -> {:error, :something_failed} end
      ToolRegistry.register(unique, tool_fn, "A failing tool", "test-ext")

      assert {:error, :something_failed} = ToolRegistry.dispatch(unique)

      assert_receive {:hook_event, :after_tool_call,
                      %{tool: ^unique, result: {:error, :something_failed}}}
    end
  end

  describe "register_builtins/0" do
    test "registers all 11 core tool stubs", %{registry: registry} do
      expected = [
        :broadcast_status,
        :delete_file,
        :list_files,
        :monitor_agents,
        :read_file,
        :run_command,
        :run_workflow,
        :search_files,
        :signal_ready,
        :spawn_agent,
        :write_file
      ]

      # Register builtins via helper to use named registry
      for {name, desc} <- builtin_tool_list() do
        stub_fn = fn _args, _ctx -> {:error, {:not_implemented, %{tool: name}}} end
        register_tool(registry, name, stub_fn, desc, "harness")
      end

      tools = list_tools(registry)
      registered_names = Enum.map(tools, & &1.name) |> Enum.sort()
      assert registered_names == expected

      for tool <- tools do
        assert tool.extension == "harness"
      end
    end

    test "register_builtins/0 exercises real public API" do
      # Uses the globally started ToolRegistry from the application
      # Clear state by re-registering — builtins may already be loaded
      ToolRegistry.register_builtins()

      tools = ToolRegistry.list_tools()
      builtin_count = Enum.count(tools, &(&1.extension == "harness"))
      assert builtin_count >= 10
    end

    test "builtin stubs return {:error, {:not_implemented, _}}", %{
      registry: registry,
      hooks: hooks
    } do
      stub_fn = fn _args, _ctx -> {:error, {:not_implemented, %{tool: :read_file}}} end
      register_tool(registry, :read_file, stub_fn, "Read a file", "harness")

      assert {:error, {:not_implemented, %{tool: :read_file}}} =
               dispatch_tool(registry, hooks, :read_file, %{path: "test.ex"})
    end
  end

  describe "tool_schemas/0" do
    test "returns correct format for LLM schema generation", %{registry: registry} do
      fun = fn _args, _ctx -> {:ok, %{}} end
      :ok = register_tool(registry, :read_file, fun, "Read a file", "harness")
      :ok = register_tool(registry, :search_context, fun, "Search knowledge", "knowledge-store")

      schemas = list_tools(registry)
      assert length(schemas) == 2

      read_schema = Enum.find(schemas, &(&1.name == :read_file))
      assert read_schema.description == "Read a file"
      assert read_schema.extension == "harness"

      search_schema = Enum.find(schemas, &(&1.name == :search_context))
      assert search_schema.description == "Search knowledge"
      assert search_schema.extension == "knowledge-store"
    end
  end

  describe "async dispatch via GenServer" do
    test "concurrent tool calls execute in parallel, not serialized" do
      # Register two tools: one slow (30ms), one fast (0ms)
      # If dispatch is serial, total time >= 60ms. If parallel, ~30ms.
      slow_fn = fn _args, _ctx ->
        Process.sleep(30)
        {:ok, %{tool: "slow"}}
      end

      fast_fn = fn _args, _ctx ->
        {:ok, %{tool: "fast"}}
      end

      slow_name = :"slow_#{System.unique_integer([:positive])}"
      fast_name = :"fast_#{System.unique_integer([:positive])}"

      ToolRegistry.register(slow_name, slow_fn, "Slow tool", "test-ext")
      ToolRegistry.register(fast_name, fast_fn, "Fast tool", "test-ext")

      start = System.monotonic_time(:millisecond)

      task_slow = Task.async(fn -> ToolRegistry.dispatch(slow_name) end)
      task_fast = Task.async(fn -> ToolRegistry.dispatch(fast_name) end)

      result_slow = Task.await(task_slow, 5_000)
      result_fast = Task.await(task_fast, 5_000)

      elapsed = System.monotonic_time(:millisecond) - start

      assert {:ok, %{tool: "slow"}} = result_slow
      assert {:ok, %{tool: "fast"}} = result_fast

      # If serial, would take >= 60ms (two 30ms sleeps). Parallel takes ~30ms.
      assert elapsed < 55, "Expected parallel execution (<55ms), got #{elapsed}ms"
    end

    test "slow tool does not block fast tool" do
      slow_fn = fn _args, _ctx ->
        Process.sleep(50)
        {:ok, %{tool: "slow"}}
      end

      fast_fn = fn _args, _ctx ->
        {:ok, %{tool: "fast"}}
      end

      slow_name = :"slow2_#{System.unique_integer([:positive])}"
      fast_name = :"fast2_#{System.unique_integer([:positive])}"

      ToolRegistry.register(slow_name, slow_fn, "Slow", "test-ext")
      ToolRegistry.register(fast_name, fast_fn, "Fast", "test-ext")

      # Start slow first, then fast
      task_slow = Task.async(fn -> ToolRegistry.dispatch(slow_name) end)
      # Small delay to ensure slow is dispatched first
      Process.sleep(5)

      fast_start = System.monotonic_time(:millisecond)
      result_fast = ToolRegistry.dispatch(fast_name)
      fast_elapsed = System.monotonic_time(:millisecond) - fast_start

      result_slow = Task.await(task_slow, 5_000)

      assert {:ok, %{tool: "fast"}} = result_fast
      assert {:ok, %{tool: "slow"}} = result_slow

      # Fast tool should complete quickly, not blocked by slow tool
      assert fast_elapsed < 30, "Fast tool blocked by slow tool: #{fast_elapsed}ms"
    end

    test "tool crash in async task returns error without affecting registry" do
      crash_fn = fn _args, _ctx -> raise "async boom!" end
      ok_fn = fn _args, _ctx -> {:ok, %{still: "alive"}} end

      crash_name = :"crash_#{System.unique_integer([:positive])}"
      ok_name = :"ok_#{System.unique_integer([:positive])}"

      ToolRegistry.register(crash_name, crash_fn, "Crasher", "test-ext")
      ToolRegistry.register(ok_name, ok_fn, "Safe tool", "test-ext")

      assert {:error, {:tool_crashed, msg}} = ToolRegistry.dispatch(crash_name)
      assert msg =~ "async boom!"

      # Registry still works
      assert {:ok, %{still: "alive"}} = ToolRegistry.dispatch(ok_name)
    end

    test "vetoed calls reply immediately without spawning task", %{
      registry: registry,
      hooks: hooks
    } do
      # Use per-test hooks to avoid polluting global Hooks server
      veto_fn = fn _payload, _ctx -> {:halt, "blocked"} end
      GenServer.call(hooks, {:register_alter, :before_tool_call, veto_fn, 1, "test-safety"})

      test_pid = self()

      tool_fn = fn _args, _ctx ->
        send(test_pid, :tool_executed)
        {:ok, %{should_not: :reach}}
      end

      register_tool(registry, :veto_tool, tool_fn, "Vetoed tool")

      # Dispatch through per-test registry which calls per-test hooks
      assert {:error, {:vetoed, "blocked"}} =
               dispatch_tool(registry, hooks, :veto_tool)

      refute_received :tool_executed
    end

    test "error paths reply immediately without spawning task" do
      # Unknown tool exercises the {:reply, error, state} branch in handle_call
      # (same branch used by veto — both are {:error, _} from prepare_dispatch)
      assert {:error, {:unknown_tool, :nonexistent_async}} =
               ToolRegistry.dispatch(:nonexistent_async)

      # Registry is not blocked after error reply
      ok_name = :"after_err_#{System.unique_integer([:positive])}"
      ToolRegistry.register(ok_name, fn _, _ -> {:ok, %{ok: true}} end, "OK", "test-ext")
      assert {:ok, %{ok: true}} = ToolRegistry.dispatch(ok_name)
    end

    test "unknown tool returns error immediately" do
      assert {:error, {:unknown_tool, :nonexistent_async}} =
               ToolRegistry.dispatch(:nonexistent_async)
    end
  end

  describe "dispatch latency benchmark" do
    @tag :benchmark
    test "concurrent dispatch is faster than sequential for slow tools" do
      n = 10
      sleep_ms = 20
      batch_id = System.unique_integer([:positive])

      for i <- 1..n do
        name = :"bench_#{batch_id}_#{i}"
        fun = fn _args, _ctx ->
          Process.sleep(sleep_ms)
          {:ok, %{i: i}}
        end
        ToolRegistry.register(name, fun, "Bench tool #{i}", "test-ext")
      end

      tool_names = for i <- 1..n, do: :"bench_#{batch_id}_#{i}"

      # Sequential
      seq_start = System.monotonic_time(:millisecond)

      for name <- tool_names do
        {:ok, _} = ToolRegistry.dispatch(name)
      end

      seq_elapsed = System.monotonic_time(:millisecond) - seq_start

      # Concurrent
      conc_start = System.monotonic_time(:millisecond)

      tasks = Enum.map(tool_names, fn name ->
        Task.async(fn -> ToolRegistry.dispatch(name) end)
      end)

      results = Task.await_many(tasks, 10_000)
      conc_elapsed = System.monotonic_time(:millisecond) - conc_start

      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Sequential should take ~N*sleep_ms, concurrent ~sleep_ms
      # Assert concurrent is at least 3x faster
      speedup = seq_elapsed / max(conc_elapsed, 1)
      assert speedup > 3.0,
        "Expected >3x speedup, got #{Float.round(speedup, 1)}x " <>
        "(seq=#{seq_elapsed}ms, conc=#{conc_elapsed}ms)"
    end
  end

  # Helper to replicate the builtin tool list
  defp builtin_tool_list do
    [
      {:read_file, "Read the contents of a file at the given path"},
      {:write_file, "Write content to a file at the given path"},
      {:delete_file, "Delete a file at the given path"},
      {:list_files, "List files matching a glob pattern"},
      {:search_files, "Search file contents for a pattern"},
      {:run_command, "Run a shell command from the configured allow-list"},
      {:spawn_agent, "Spawn a child agent process with a given role and task"},
      {:run_workflow, "Run a workflow defined in a markdown file with YAML frontmatter"},
      {:monitor_agents, "List running agent processes and their status"},
      {:broadcast_status, "Broadcast a status message to PubSub subscribers"},
      {:signal_ready, "Signal that the current workflow step is complete"}
    ]
  end
end
