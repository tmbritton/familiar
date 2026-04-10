defmodule Familiar.Hooks do
  @moduledoc """
  Lifecycle hook dispatch for the agent harness.

  Manages two types of hooks:

    * **Alter hooks** — synchronous pipeline that can modify payloads or veto
      operations. Handlers run in priority order (lower number first). Each
      handler is isolated with a timeout and circuit breaker.

    * **Event hooks** — async broadcast via `Familiar.Activity` PubSub.
      Subscribers are crash-isolated by the PubSub infrastructure.

  ## MVP Hooks

    * `on_startup` (event) — fired after all extensions loaded
    * `on_agent_start` (event) — agent initialized with a role
    * `before_tool_call` (alter) — safety enforcement, arg validation
    * `after_tool_call` (event) — result logging, knowledge capture
    * `on_agent_complete` (event) — post-task hygiene, cleanup
    * `on_agent_error` (event) — error logging, failure analysis
    * `on_file_changed` (event) — knowledge store freshness
    * `on_shutdown` (event) — graceful shutdown cleanup
  """

  use GenServer

  require Logger

  alias Familiar.Activity

  @default_handler_timeout 5_000
  @default_event_handler_timeout 10_000
  @default_mailbox_warning_threshold 100
  @mailbox_warning_cooldown_ms 10_000
  @circuit_breaker_threshold 3

  # -- Public API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register an alter hook handler.

  Handlers are sorted by priority (lower runs first). The `handler_fn`
  receives `(payload, context)` and must return `{:ok, payload}` or
  `{:halt, reason}`.
  """
  @spec register_alter_hook(atom(), function(), integer(), String.t()) :: :ok
  def register_alter_hook(hook, handler_fn, priority \\ 100, extension_name)
      when is_atom(hook) and is_function(handler_fn) do
    GenServer.call(__MODULE__, {:register_alter, hook, handler_fn, priority, extension_name})
  end

  @doc """
  Register an event hook handler.

  The `handler_fn` receives `(payload)` and is called asynchronously
  via PubSub when the event fires.
  """
  @spec register_event_hook(atom(), function(), String.t()) :: :ok
  def register_event_hook(hook, handler_fn, extension_name)
      when is_atom(hook) and is_function(handler_fn) do
    GenServer.call(__MODULE__, {:register_event, hook, handler_fn, extension_name})
  end

  @doc """
  Run the alter hook pipeline for the given hook name.

  Returns `{:ok, possibly_modified_payload}` or `{:halt, reason}`.
  """
  @spec alter(atom(), map(), map()) :: {:ok, map()} | {:halt, term()}
  def alter(hook, payload, context \\ %{}) when is_atom(hook) do
    GenServer.call(__MODULE__, {:alter, hook, payload, context}, :infinity)
  end

  @doc """
  Broadcast an event hook.

  Fire-and-forget — always returns `:ok`. Event handlers run in their
  own PubSub subscriber processes.
  """
  @spec event(atom(), map()) :: :ok
  def event(hook, payload \\ %{}) when is_atom(hook) do
    topic = Activity.topic("hooks:#{hook}")

    Phoenix.PubSub.broadcast(
      Familiar.PubSub,
      topic,
      {:hook_event, hook, payload}
    )

    :ok
  rescue
    _ -> :ok
  end

  @doc "Reset a circuit-broken handler, re-enabling it."
  @spec reset_circuit_breaker(String.t()) :: :ok
  def reset_circuit_breaker(handler_key) do
    GenServer.call(__MODULE__, {:reset_circuit_breaker, handler_key})
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    on_handler_error = Keyword.get(opts, :on_handler_error)

    {:ok,
     %{
       alter_hooks: %{},
       event_handlers: %{},
       circuit_breaker: %{},
       subscribed_topics: MapSet.new(),
       last_mailbox_warning: nil,
       on_handler_error: on_handler_error
     }}
  end

  @impl true
  def handle_call({:register_alter, hook, handler_fn, priority, ext_name}, _from, state) do
    handler = %{fn: handler_fn, priority: priority, extension: ext_name}
    key = handler_key(hook, ext_name, priority)
    handler = Map.put(handler, :key, key)

    hooks =
      state.alter_hooks
      |> Map.update(hook, [handler], fn existing ->
        [handler | existing] |> Enum.sort_by(& &1.priority)
      end)

    {:reply, :ok, %{state | alter_hooks: hooks}}
  end

  def handle_call({:register_event, hook, handler_fn, ext_name}, _from, state) do
    topic = Activity.topic("hooks:#{hook}")
    handler = %{fn: handler_fn, extension: ext_name, topic: topic}

    # Subscribe only once per topic to avoid duplicate message delivery
    state =
      if MapSet.member?(state.subscribed_topics, topic) do
        state
      else
        Phoenix.PubSub.subscribe(Familiar.PubSub, topic)
        %{state | subscribed_topics: MapSet.put(state.subscribed_topics, topic)}
      end

    handlers =
      state.event_handlers
      |> Map.update(hook, [handler], fn existing -> [handler | existing] end)

    {:reply, :ok, %{state | event_handlers: handlers}}
  end

  def handle_call({:alter, hook, payload, context}, _from, state) do
    handlers = Map.get(state.alter_hooks, hook, [])
    {result, new_state} = run_alter_pipeline(handlers, payload, context, state)
    {:reply, result, new_state}
  end

  def handle_call({:reset_circuit_breaker, handler_key}, _from, state) do
    cb = Map.delete(state.circuit_breaker, handler_key)
    {:reply, :ok, %{state | circuit_breaker: cb}}
  end

  @impl true
  def handle_info({:hook_event, hook, payload}, state) do
    state = check_mailbox_depth(state)
    handlers = Map.get(state.event_handlers, hook, [])

    for handler <- handlers do
      spawn_event_handler(handler, hook, payload, state.on_handler_error)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  defp run_alter_pipeline(handlers, payload, context, state) do
    Enum.reduce_while(handlers, {{:ok, payload}, state}, fn handler,
                                                            {{:ok, current}, acc_state} ->
      if circuit_broken?(handler.key, acc_state) do
        {:cont, {{:ok, current}, acc_state}}
      else
        process_alter_result(handler, current, context, acc_state)
      end
    end)
  end

  defp process_alter_result(handler, current, context, acc_state) do
    case execute_alter_handler(handler, current, context, acc_state.on_handler_error) do
      {:ok, modified} ->
        new_state = reset_failure_count(handler.key, acc_state)
        {:cont, {{:ok, modified}, new_state}}

      {:halt, reason} ->
        new_state = reset_failure_count(handler.key, acc_state)
        {:halt, {{:halt, reason}, new_state}}

      {:error, :handler_failed} ->
        new_state = record_failure(handler, acc_state)
        {:cont, {{:ok, current}, new_state}}
    end
  end

  defp execute_alter_handler(handler, payload, context, on_error) do
    task =
      Task.Supervisor.async_nolink(Familiar.TaskSupervisor, fn ->
        handler.fn.(payload, context)
      end)

    timeout = handler_timeout()

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, modified}} when is_map(modified) ->
        {:ok, modified}

      {:ok, {:halt, reason}} ->
        {:halt, reason}

      {:ok, other} ->
        report_handler_error(on_error, handler.extension, :alter, :unexpected_value, other)
        {:error, :handler_failed}

      {:exit, reason} ->
        report_handler_error(on_error, handler.extension, :alter, :crashed, reason)
        {:error, :handler_failed}

      nil ->
        report_handler_error(on_error, handler.extension, :alter, :timed_out, timeout)

        {:error, :handler_failed}
    end
  end

  defp circuit_broken?(handler_key, state) do
    Map.get(state.circuit_breaker, handler_key, 0) >= @circuit_breaker_threshold
  end

  defp record_failure(handler, state) do
    count = Map.get(state.circuit_breaker, handler.key, 0) + 1

    if count >= @circuit_breaker_threshold do
      Logger.warning(
        "[Hooks] Circuit breaker tripped for '#{handler.extension}' — " <>
          "handler disabled after #{@circuit_breaker_threshold} consecutive failures"
      )
    end

    %{state | circuit_breaker: Map.put(state.circuit_breaker, handler.key, count)}
  end

  defp reset_failure_count(handler_key, state) do
    if Map.has_key?(state.circuit_breaker, handler_key) do
      %{state | circuit_breaker: Map.delete(state.circuit_breaker, handler_key)}
    else
      state
    end
  end

  defp spawn_event_handler(handler, hook, payload, on_error) do
    case Task.Supervisor.start_child(Familiar.TaskSupervisor, fn ->
           run_event_handler_with_timeout(handler, hook, payload, on_error)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        report_handler_error(on_error, handler.extension, hook, :spawn_failed, reason)
    end
  catch
    :exit, reason ->
      report_handler_error(on_error, handler.extension, hook, :spawn_failed, reason)
  end

  defp run_event_handler_with_timeout(handler, hook, payload, on_error) do
    timeout = event_handler_timeout()

    task =
      Task.Supervisor.async_nolink(Familiar.TaskSupervisor, fn ->
        handler.fn.(payload)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, _} ->
        :ok

      {:exit, reason} ->
        report_handler_error(on_error, handler.extension, hook, :crashed, reason)

      nil ->
        report_handler_error(on_error, handler.extension, hook, :timed_out, timeout)
    end
  end

  defp report_handler_error(on_error, extension, hook, kind, detail) do
    msg =
      case kind do
        :crashed ->
          "[Hooks] Event handler '#{extension}' crashed for #{hook}: #{inspect(detail)}"

        :timed_out ->
          "[Hooks] Event handler '#{extension}' timed out for #{hook} (#{detail}ms)"

        :spawn_failed ->
          "[Hooks] Failed to spawn event handler '#{extension}' for #{hook}: #{inspect(detail)}"

        :unexpected_value ->
          "[Hooks] Alter handler '#{extension}' returned unexpected value for #{hook}: #{inspect(detail)}"
      end

    Logger.warning(msg)

    if is_function(on_error, 1) do
      on_error.(%{extension: extension, hook: hook, kind: kind, detail: detail})
    end
  end

  defp check_mailbox_depth(state) do
    {:message_queue_len, len} = Process.info(self(), :message_queue_len)
    threshold = mailbox_warning_threshold()

    if len > threshold do
      now = System.monotonic_time(:millisecond)
      last = state.last_mailbox_warning

      # `nil` sentinel means "never warned yet" — always fire. Guards against
      # a millisecond-resolution race on fresh GenServers where a numeric
      # init value could make `now - last == cooldown_ms` (not `>`) on the
      # very first check.
      if is_nil(last) or now - last > @mailbox_warning_cooldown_ms do
        Logger.warning("[Hooks] Mailbox depth #{len} exceeds threshold #{threshold}")
        %{state | last_mailbox_warning: now}
      else
        state
      end
    else
      state
    end
  end

  defp event_handler_timeout do
    Application.get_env(:familiar, __MODULE__, [])
    |> Keyword.get(:event_handler_timeout, @default_event_handler_timeout)
  end

  defp mailbox_warning_threshold do
    Application.get_env(:familiar, __MODULE__, [])
    |> Keyword.get(:mailbox_warning_threshold, @default_mailbox_warning_threshold)
  end

  defp handler_timeout do
    Application.get_env(:familiar, __MODULE__, [])
    |> Keyword.get(:handler_timeout, @default_handler_timeout)
  end

  defp handler_key(hook, ext_name, priority) do
    "#{hook}:#{ext_name}:#{priority}"
  end
end
