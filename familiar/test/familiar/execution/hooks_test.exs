defmodule Familiar.HooksTest do
  use ExUnit.Case, async: true

  alias Familiar.Hooks

  setup do
    # Start a fresh Hooks GenServer for each test
    # on_handler_error callback allows tests to observe errors via messages
    # instead of unreliable capture_log from async Task processes
    test_pid = self()
    name = :"hooks_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Hooks, name: name, on_handler_error: fn info -> send(test_pid, {:handler_error, info}) end}
    )

    {:ok, hooks_name: name}
  end

  # Helper to call the named Hooks instance directly
  defp register_alter(name, hook, handler_fn, priority, ext_name) do
    GenServer.call(name, {:register_alter, hook, handler_fn, priority, ext_name})
  end

  defp register_event(name, hook, handler_fn, ext_name) do
    GenServer.call(name, {:register_event, hook, handler_fn, ext_name})
  end

  defp run_alter(name, hook, payload, context \\ %{}) do
    GenServer.call(name, {:alter, hook, payload, context}, :infinity)
  end

  defp reset_cb(name, handler_key) do
    GenServer.call(name, {:reset_circuit_breaker, handler_key})
  end

  describe "alter pipeline" do
    test "runs handlers in priority order", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.put(payload, :first, true)}
        end,
        10,
        "ext-a"
      )

      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.put(payload, :second, true)}
        end,
        20,
        "ext-b"
      )

      assert {:ok, result} = run_alter(name, :before_tool_call, %{tool: "read_file"})
      assert result.first == true
      assert result.second == true
    end

    test "lower priority number runs first", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.update(payload, :order, ["high"], &(&1 ++ ["high"]))}
        end,
        100,
        "high-priority"
      )

      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.update(payload, :order, ["low"], &(&1 ++ ["low"]))}
        end,
        1,
        "low-priority"
      )

      assert {:ok, %{order: ["low", "high"]}} =
               run_alter(name, :before_tool_call, %{})
    end

    test "handler can veto with {:halt, reason}", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn _payload, _ctx ->
          {:halt, "blocked by safety"}
        end,
        1,
        "safety"
      )

      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.put(payload, :should_not_run, true)}
        end,
        50,
        "other"
      )

      assert {:halt, "blocked by safety"} =
               run_alter(name, :before_tool_call, %{tool: "rm_rf"})
    end

    test "returns {:ok, payload} when no handlers registered", %{hooks_name: name} do
      assert {:ok, %{tool: "test"}} = run_alter(name, :before_tool_call, %{tool: "test"})
    end

    test "passes context to handlers", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn payload, ctx ->
          {:ok, Map.put(payload, :agent, ctx.agent_id)}
        end,
        100,
        "ctx-ext"
      )

      assert {:ok, %{agent: "agent-1"}} =
               run_alter(name, :before_tool_call, %{}, %{agent_id: "agent-1"})
    end
  end

  describe "alter pipeline error isolation" do
    test "handler that raises is skipped, payload unmodified", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn _payload, _ctx ->
          raise "boom"
        end,
        1,
        "bad-ext"
      )

      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.put(payload, :reached, true)}
        end,
        50,
        "good-ext"
      )

      assert {:ok, result} = run_alter(name, :before_tool_call, %{tool: "test"})
      assert result.reached == true
      assert result.tool == "test"

      # Handler error reported via callback — may be :crashed or :timed_out under load
      assert_receive {:handler_error, %{extension: "bad-ext", kind: kind}}, 1_000
      assert kind in [:crashed, :timed_out]
    end

    test "handler that times out is killed and skipped", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn _payload, _ctx ->
          # Sleep longer than the configured handler_timeout (50ms in test env)
          Process.sleep(500)
          {:ok, %{}}
        end,
        1,
        "slow-ext"
      )

      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          {:ok, Map.put(payload, :reached, true)}
        end,
        50,
        "fast-ext"
      )

      assert {:ok, result} = run_alter(name, :before_tool_call, %{tool: "test"})
      assert result.reached == true

      assert_receive {:handler_error, %{extension: "slow-ext", kind: :timed_out}}, 1_000
    end

    @tag timeout: 30_000
    test "circuit breaker activates after 3 consecutive failures", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn _payload, _ctx ->
          raise "always fails"
        end,
        1,
        "flaky-ext"
      )

      # First 3 calls trigger failures and eventually the circuit breaker
      for _ <- 1..3 do
        run_alter(name, :before_tool_call, %{})
      end

      # Should have received 3 handler errors (crash or timeout)
      for _ <- 1..3 do
        assert_receive {:handler_error, %{extension: "flaky-ext"}}, 1_000
      end

      # 4th call — handler should be skipped silently (circuit broken)
      assert {:ok, %{}} = run_alter(name, :before_tool_call, %{})

      # No handler error because handler was skipped entirely
      refute_receive {:handler_error, %{extension: "flaky-ext"}}, 100
    end

    test "circuit breaker reset re-enables handler", %{hooks_name: name} do
      register_alter(
        name,
        :before_tool_call,
        fn payload, _ctx ->
          if Map.get(payload, :should_fail) do
            raise "fail"
          else
            {:ok, Map.put(payload, :handler_ran, true)}
          end
        end,
        1,
        "resettable"
      )

      # Trip the circuit breaker
      for _ <- 1..3 do
        run_alter(name, :before_tool_call, %{should_fail: true})
      end

      # Drain handler error messages
      for _ <- 1..3 do
        assert_receive {:handler_error, %{extension: "resettable"}}, 1_000
      end

      # Verify handler is skipped
      assert {:ok, result} = run_alter(name, :before_tool_call, %{})
      refute Map.has_key?(result, :handler_ran)

      # Reset and verify handler runs again
      reset_cb(name, "before_tool_call:resettable:1")

      assert {:ok, %{handler_ran: true}} = run_alter(name, :before_tool_call, %{})
    end
  end

  describe "event dispatch" do
    test "event reaches subscribed handler", %{hooks_name: name} do
      test_pid = self()

      register_event(
        name,
        :on_agent_complete,
        fn _payload ->
          send(test_pid, :event_received)
        end,
        "listener-ext"
      )

      # Fire the event — this broadcasts via Activity PubSub
      Hooks.event(:on_agent_complete, %{agent: "test"})

      assert_receive :event_received, 1_000
    end

    test "multiple handlers for same event all receive it", %{hooks_name: name} do
      test_pid = self()

      register_event(
        name,
        :on_agent_complete,
        fn _payload ->
          send(test_pid, :handler_1)
        end,
        "ext-1"
      )

      register_event(
        name,
        :on_agent_complete,
        fn _payload ->
          send(test_pid, :handler_2)
        end,
        "ext-2"
      )

      Hooks.event(:on_agent_complete, %{})

      assert_receive :handler_1, 1_000
      assert_receive :handler_2, 1_000
    end

    test "crashing event handler does not affect other handlers", %{hooks_name: name} do
      test_pid = self()

      register_event(
        name,
        :after_tool_call,
        fn _payload ->
          raise "event handler crash"
        end,
        "crasher"
      )

      register_event(
        name,
        :after_tool_call,
        fn _payload ->
          send(test_pid, :survivor_received)
        end,
        "survivor"
      )

      Hooks.event(:after_tool_call, %{})

      assert_receive :survivor_received, 1_000
      # raise may surface as :crashed or :timed_out depending on Task.yield timing
      assert_receive {:handler_error, %{extension: "crasher", kind: kind}}, 1_000
      assert kind in [:crashed, :timed_out]
    end

    test "slow event handler is killed after timeout and warning logged", %{hooks_name: name} do
      test_pid = self()

      register_event(
        name,
        :after_tool_call,
        fn _payload ->
          # Sleep longer than event_handler_timeout (50ms in test env)
          Process.sleep(500)
          send(test_pid, :should_not_arrive)
        end,
        "slow-event-ext"
      )

      Hooks.event(:after_tool_call, %{})

      assert_receive {:handler_error, %{extension: "slow-event-ext", kind: :timed_out}}, 1_000
      refute_received :should_not_arrive
    end

    test "GenServer survives when event handler exits abnormally", %{hooks_name: name} do
      test_pid = self()

      register_event(
        name,
        :after_tool_call,
        fn _payload ->
          exit(:handler_abort)
        end,
        "exiting-ext"
      )

      register_event(
        name,
        :after_tool_call,
        fn _payload ->
          send(test_pid, :survivor_ok)
        end,
        "survivor-ext"
      )

      Hooks.event(:after_tool_call, %{})

      assert_receive :survivor_ok, 1_000

      # exit/1 may surface as :crashed or :timed_out depending on Task.yield timing
      assert_receive {:handler_error, %{extension: "exiting-ext", kind: kind}}, 1_000
      assert kind in [:crashed, :timed_out]

      # GenServer is still alive
      assert Process.alive?(Process.whereis(name))
    end
  end

  describe "mailbox depth warning" do
    test "warns when mailbox exceeds threshold", %{hooks_name: name} do
      register_event(
        name,
        :on_file_changed,
        fn _payload -> :ok end,
        "file-ext"
      )

      # Fresh GenServer — last_mailbox_warning starts as nil until a warning
      # is emitted. We assert it becomes a monotonic timestamp below.
      assert :sys.get_state(name).last_mailbox_warning == nil

      # Suspend so every message lands in the mailbox before the first
      # handle_info runs check_mailbox_depth/1.
      :sys.suspend(name)

      for _ <- 1..20 do
        send(name, {:hook_event, :on_file_changed, %{path: "test.ex"}})
      end

      :sys.resume(name)

      # Deterministic sync via a regular GenServer.call: calls and sends go
      # into the same mailbox in FIFO order, so this register_event runs only
      # after all 20 hook_event messages have been processed. (`:sys.get_state`
      # is NOT a reliable sync point — it is delivered as a system message and
      # the gen_server outer receive checks system messages *before* regular
      # messages, so it can return before hook_events are drained.) Once this
      # call returns, the first handle_info has already run check_mailbox_depth
      # with len=20, which bumps last_mailbox_warning — observing the state is
      # race-free. `capture_log` is unreliable here because log handlers are
      # installed per-group-leader and can miss messages under scheduler
      # contention from other async tests.
      register_event(name, :on_file_changed, fn _ -> :ok end, "sync-ext")

      after_stamp = :sys.get_state(name).last_mailbox_warning

      assert is_integer(after_stamp),
             "expected check_mailbox_depth/1 to set last_mailbox_warning after mailbox exceeded threshold"
    end
  end
end
