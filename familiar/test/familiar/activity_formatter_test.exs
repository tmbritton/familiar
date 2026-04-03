defmodule Familiar.ActivityFormatterTest do
  use ExUnit.Case, async: true

  alias Familiar.Activity.Event
  alias Familiar.ActivityFormatter

  describe "format/2" do
    test "formats file_read event" do
      event = %Event{type: :file_read, detail: "lib/auth.ex", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Reading lib/auth.ex"
    end

    test "formats file_write event" do
      event = %Event{type: :file_write, detail: "lib/auth.ex", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Writing lib/auth.ex"
    end

    test "formats tool_call event" do
      event = %Event{type: :tool_call, detail: "search_context", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Tool: search_context"
    end

    test "formats tool_call event with result" do
      event = %Event{type: :tool_call, detail: "search_context", result: "3 results", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Tool: search_context → 3 results"
    end

    test "formats knowledge_search event" do
      event = %Event{type: :knowledge_search, detail: "auth patterns", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Searching knowledge: auth patterns"
    end

    test "formats step_started event" do
      event = %Event{type: :step_started, detail: "context-retrieval", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "Starting: context-retrieval"
    end

    test "formats step_complete event" do
      event = %Event{type: :step_complete, detail: "context-retrieval", result: "5 entries", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "Completed: context-retrieval (5 entries)"
    end

    test "formats agent_spawned event" do
      event = %Event{type: :agent_spawned, detail: "coder", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Spawned agent: coder"
    end

    test "formats agent_complete event" do
      event = %Event{type: :agent_complete, detail: "coder", result: "4 files modified", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Agent done: coder — 4 files modified"
    end

    test "formats status event" do
      event = %Event{type: :status, result: "Waiting for provider", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Waiting for provider"
    end

    test "formats unknown event type" do
      event = %Event{type: :custom_event, detail: "something", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  custom_event: something"
    end

    test "handles nil detail gracefully" do
      event = %Event{type: :file_read, timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event) == "  Reading unknown"
    end

    test "truncates to 80 columns" do
      long_path = String.duplicate("a", 100)
      event = %Event{type: :file_read, detail: long_path, timestamp: DateTime.utc_now()}
      formatted = ActivityFormatter.format(event)
      assert String.length(formatted) <= 80
      assert String.ends_with?(formatted, "\u2026")
    end

    test "appends hint for file_read" do
      event = %Event{type: :file_read, detail: "f.ex", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event, hint: true) =~ "(checking file contents)"
    end

    test "appends hint for knowledge_search" do
      event = %Event{type: :knowledge_search, detail: "q", timestamp: DateTime.utc_now()}
      assert ActivityFormatter.format(event, hint: true) =~ "(querying project context)"
    end
  end

  describe "heartbeat/0" do
    test "returns heartbeat indicator" do
      assert ActivityFormatter.heartbeat() == "  ..."
    end
  end
end
