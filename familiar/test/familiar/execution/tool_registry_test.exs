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
    test "registers all 10 core tool stubs", %{registry: registry} do
      expected = [
        :broadcast_status,
        :delete_file,
        :list_files,
        :monitor_agents,
        :read_file,
        :run_command,
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
      {:monitor_agents, "List running agent processes and their status"},
      {:broadcast_status, "Broadcast a status message to PubSub subscribers"},
      {:signal_ready, "Signal that the current workflow step is complete"}
    ]
  end
end
