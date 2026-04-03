defmodule Familiar.Planning.Trail do
  @moduledoc """
  PubSub broadcasting for planning reasoning trail events.

  Streams high-level semantic events (file reads, knowledge searches,
  verification results) during spec generation so clients can display
  real-time progress. Events are fire-and-forget — broadcasting never
  blocks or fails the spec generation pipeline.
  """

  import Ecto.Query

  alias Familiar.Planning.Session
  alias Familiar.Repo

  defmodule Event do
    @moduledoc """
    A single reasoning trail event.

    Fields:
    - `type` — event kind: `:file_read`, `:knowledge_search`, `:verification_result`, `:spec_started`, `:spec_complete`
    - `path` — file path or search query (nil for lifecycle events)
    - `result` — outcome summary (e.g., "verified", "not found", verification counts)
    - `timestamp` — when the event occurred
    """
    @type t :: %__MODULE__{
            type: atom(),
            path: String.t() | nil,
            result: String.t() | nil,
            timestamp: DateTime.t()
          }

    @enforce_keys [:type, :timestamp]
    defstruct [:type, :path, :result, :timestamp]
  end

  @doc """
  Build a trail topic string for a given session ID.
  """
  @spec topic(integer() | String.t()) :: String.t()
  def topic(session_id) do
    "planning:trail:#{session_id}"
  end

  @doc """
  Broadcast a trail event to all subscribers of the session's trail topic.

  Returns `{:ok, :broadcast}` always — errors are silently ignored to avoid
  blocking spec generation.
  """
  @spec broadcast(integer(), Event.t()) :: {:ok, :broadcast}
  def broadcast(session_id, %Event{} = event) do
    Phoenix.PubSub.broadcast(Familiar.PubSub, topic(session_id), {:trail_event, event})
    {:ok, :broadcast}
  rescue
    _ -> {:ok, :broadcast}
  end

  @doc """
  Subscribe the calling process to trail events for a session.
  """
  @spec subscribe(integer()) :: {:ok, :subscribed} | {:error, {atom(), map()}}
  def subscribe(session_id) do
    case Phoenix.PubSub.subscribe(Familiar.PubSub, topic(session_id)) do
      :ok -> {:ok, :subscribed}
      {:error, reason} -> {:error, {:subscribe_failed, %{reason: reason}}}
    end
  end

  @doc """
  Subscribe to trail events with automatic heartbeat.

  Sends `{:trail_heartbeat, pid}` to the calling process if no trail
  event is received within `interval_ms` (default 5000). The timer
  resets on each real event. Call `cancel_heartbeat/1` to stop.

  Returns `{:ok, timer_ref}`.
  """
  @spec subscribe_with_heartbeat(integer(), keyword()) :: {:ok, reference()}
  def subscribe_with_heartbeat(session_id, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 5_000)
    {:ok, :subscribed} = subscribe(session_id)
    ref = Process.send_after(self(), {:trail_heartbeat, self()}, interval)
    {:ok, ref}
  end

  @doc """
  Reset the heartbeat timer. Call this when a real trail event is received.

  Cancels the old timer and starts a new one with the same interval.
  Returns the new timer reference.
  """
  @spec reset_heartbeat(reference(), keyword()) :: reference()
  def reset_heartbeat(timer_ref, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 5_000)
    Process.cancel_timer(timer_ref)
    Process.send_after(self(), {:trail_heartbeat, self()}, interval)
  end

  @doc """
  Cancel a heartbeat timer.
  """
  @spec cancel_heartbeat(reference()) :: {:ok, :cancelled}
  def cancel_heartbeat(timer_ref) do
    Process.cancel_timer(timer_ref)
    {:ok, :cancelled}
  end

  @doc """
  Check whether progressive hints should be shown.

  Returns `{:ok, boolean}` — true if fewer than 3 planning sessions
  have been completed.
  """
  @spec show_hints?() :: {:ok, boolean()}
  def show_hints? do
    count =
      from(s in Session, where: s.status == "completed")
      |> Repo.aggregate(:count, :id)

    {:ok, count < 3}
  rescue
    _ -> {:ok, true}
  end
end
