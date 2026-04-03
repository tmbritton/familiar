defmodule Familiar.Planning.TrailTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning.Session
  alias Familiar.Planning.Trail
  alias Familiar.Planning.Trail.Event

  describe "Event struct" do
    test "creates event with required fields" do
      event = %Event{type: :file_read, timestamp: DateTime.utc_now()}
      assert event.type == :file_read
      assert event.path == nil
      assert event.result == nil
    end

    test "creates event with all fields" do
      now = DateTime.utc_now()

      event = %Event{
        type: :file_read,
        path: "lib/auth.ex",
        result: "ok",
        timestamp: now
      }

      assert event.type == :file_read
      assert event.path == "lib/auth.ex"
      assert event.result == "ok"
      assert event.timestamp == now
    end
  end

  describe "topic/1" do
    test "builds topic string from session id" do
      assert Trail.topic(42) == "planning:trail:42"
    end
  end

  describe "broadcast/2 and subscribe/1" do
    test "broadcast delivers event to subscriber" do
      session_id = 999
      {:ok, :subscribed} = Trail.subscribe(session_id)

      event = %Event{type: :file_read, path: "lib/app.ex", timestamp: DateTime.utc_now()}
      {:ok, :broadcast} = Trail.broadcast(session_id, event)

      assert_receive {:trail_event, ^event}
    end

    test "broadcast returns {:ok, :broadcast} even when no subscribers" do
      event = %Event{type: :spec_started, timestamp: DateTime.utc_now()}
      assert {:ok, :broadcast} = Trail.broadcast(12_345, event)
    end
  end

  describe "subscribe_with_heartbeat/2" do
    test "sends heartbeat after timeout" do
      session_id = 888
      {:ok, _ref} = Trail.subscribe_with_heartbeat(session_id, interval_ms: 50)

      assert_receive {:trail_heartbeat, _pid}, 200
    end

    test "heartbeat suppressed when reset" do
      session_id = 777
      {:ok, ref} = Trail.subscribe_with_heartbeat(session_id, interval_ms: 100)

      # Reset before the heartbeat fires
      Process.sleep(50)
      new_ref = Trail.reset_heartbeat(ref, interval_ms: 200)

      # Original 100ms has passed — no heartbeat because we reset
      refute_receive {:trail_heartbeat, _}, 80

      # Clean up
      Trail.cancel_heartbeat(new_ref)
    end
  end

  describe "cancel_heartbeat/1" do
    test "returns {:ok, :cancelled}" do
      ref = Process.send_after(self(), :test, 60_000)
      assert {:ok, :cancelled} = Trail.cancel_heartbeat(ref)
    end
  end

  describe "show_hints?/0" do
    test "returns {:ok, true} when fewer than 3 completed sessions" do
      assert Trail.show_hints?() == {:ok, true}
    end

    test "returns {:ok, false} when 3 or more completed sessions exist" do
      for _ <- 1..3 do
        {:ok, session} =
          %Session{}
          |> Session.changeset(%{description: "test plan", context: "ctx"})
          |> Repo.insert()

        session
        |> Session.changeset(%{status: "completed"})
        |> Repo.update!()
      end

      assert Trail.show_hints?() == {:ok, false}
    end
  end
end
