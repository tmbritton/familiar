defmodule Familiar.Activity do
  @moduledoc """
  PubSub broadcasting for agent activity events.

  Streams status events (tool calls, step progress, completions) from
  agent processes so clients (CLI, web, channel) can display real-time
  progress. Events are fire-and-forget — broadcasting never blocks the
  agent execution pipeline.
  """

  defmodule Event do
    @moduledoc """
    A single activity event.

    Fields:
    - `type` — event kind atom (e.g., `:file_read`, `:tool_call`, `:step_started`, `:step_complete`)
    - `detail` — primary context string (file path, tool name, step name, etc.)
    - `result` — outcome summary (optional)
    - `timestamp` — when the event occurred
    """
    @type t :: %__MODULE__{
            type: atom(),
            detail: String.t() | nil,
            result: String.t() | nil,
            timestamp: DateTime.t()
          }

    @enforce_keys [:type, :timestamp]
    defstruct [:type, :detail, :result, :timestamp]
  end

  @doc """
  Build an activity topic string for a given scope ID.

  The scope can be a session, workflow, or agent process identifier.
  """
  @spec topic(integer() | String.t()) :: String.t()
  def topic(scope_id) do
    "familiar:activity:#{scope_id}"
  end

  @doc """
  Broadcast an activity event to all subscribers.

  Returns `{:ok, :broadcast}` always — errors are silently ignored
  to avoid blocking agent execution.
  """
  @spec broadcast(integer() | String.t(), Event.t()) :: {:ok, :broadcast}
  def broadcast(scope_id, %Event{} = event) do
    Phoenix.PubSub.broadcast(Familiar.PubSub, topic(scope_id), {:activity_event, event})
    {:ok, :broadcast}
  rescue
    _ -> {:ok, :broadcast}
  end

  @doc """
  Subscribe the calling process to activity events for a scope.
  """
  @spec subscribe(integer() | String.t()) :: {:ok, :subscribed}
  def subscribe(scope_id) do
    case Phoenix.PubSub.subscribe(Familiar.PubSub, topic(scope_id)) do
      :ok -> {:ok, :subscribed}
      {:error, reason} -> {:error, {:subscribe_failed, %{reason: reason}}}
    end
  end

  @doc """
  Subscribe with automatic heartbeat.

  Sends `{:activity_heartbeat, pid}` to the calling process if no
  activity event is received within `interval_ms` (default 5000).

  Returns `{:ok, timer_ref}`.
  """
  @spec subscribe_with_heartbeat(integer() | String.t(), keyword()) :: {:ok, reference()}
  def subscribe_with_heartbeat(scope_id, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 5_000)
    {:ok, :subscribed} = subscribe(scope_id)
    ref = Process.send_after(self(), {:activity_heartbeat, self()}, interval)
    {:ok, ref}
  end

  @doc """
  Reset the heartbeat timer. Call when a real activity event is received.
  Returns the new timer reference.
  """
  @spec reset_heartbeat(reference(), keyword()) :: reference()
  def reset_heartbeat(timer_ref, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 5_000)
    Process.cancel_timer(timer_ref)
    Process.send_after(self(), {:activity_heartbeat, self()}, interval)
  end

  @doc """
  Cancel a heartbeat timer.
  """
  @spec cancel_heartbeat(reference()) :: {:ok, :cancelled}
  def cancel_heartbeat(timer_ref) do
    Process.cancel_timer(timer_ref)
    {:ok, :cancelled}
  end
end
