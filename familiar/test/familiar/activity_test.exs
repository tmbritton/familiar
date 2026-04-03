defmodule Familiar.ActivityTest do
  use ExUnit.Case, async: false

  alias Familiar.Activity
  alias Familiar.Activity.Event

  describe "Event struct" do
    test "creates event with required fields" do
      event = %Event{type: :file_read, timestamp: DateTime.utc_now()}
      assert event.type == :file_read
      assert event.detail == nil
      assert event.result == nil
    end

    test "creates event with all fields" do
      event = %Event{
        type: :tool_call,
        detail: "read_file",
        result: "ok",
        timestamp: DateTime.utc_now()
      }

      assert event.detail == "read_file"
      assert event.result == "ok"
    end
  end

  describe "topic/1" do
    test "builds topic from integer" do
      assert "familiar:activity:42" = Activity.topic(42)
    end

    test "builds topic from string" do
      assert "familiar:activity:workflow-1" = Activity.topic("workflow-1")
    end
  end

  describe "broadcast/2 and subscribe/1" do
    test "subscriber receives broadcast events" do
      {:ok, :subscribed} = Activity.subscribe(99)

      event = %Event{type: :file_read, detail: "lib/test.ex", timestamp: DateTime.utc_now()}
      {:ok, :broadcast} = Activity.broadcast(99, event)

      assert_receive {:activity_event, ^event}
    end

    test "broadcast never fails" do
      event = %Event{type: :step_started, timestamp: DateTime.utc_now()}
      assert {:ok, :broadcast} = Activity.broadcast(999_999, event)
    end
  end

  describe "heartbeat" do
    test "subscribe_with_heartbeat sends heartbeat after interval" do
      {:ok, _ref} = Activity.subscribe_with_heartbeat(88, interval_ms: 50)
      assert_receive {:activity_heartbeat, _pid}, 200
    end

    test "reset_heartbeat cancels old timer and starts new one" do
      {:ok, ref} = Activity.subscribe_with_heartbeat(77, interval_ms: 5_000)
      new_ref = Activity.reset_heartbeat(ref, interval_ms: 50)
      assert new_ref != ref
      assert_receive {:activity_heartbeat, _pid}, 200
    end

    test "cancel_heartbeat stops the timer" do
      {:ok, ref} = Activity.subscribe_with_heartbeat(66, interval_ms: 50)
      {:ok, :cancelled} = Activity.cancel_heartbeat(ref)
      refute_receive {:activity_heartbeat, _pid}, 100
    end
  end
end
