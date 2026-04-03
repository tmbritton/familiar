defmodule Familiar.Planning.TrailFormatterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Familiar.Planning.Trail.Event
  alias Familiar.Planning.TrailFormatter

  describe "format/1" do
    test "formats file_read event" do
      event = %Event{type: :file_read, path: "db/migrations/001_init.sql", timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "  Reading db/migrations/001_init.sql"
    end

    test "formats knowledge_search event" do
      event = %Event{type: :knowledge_search, path: "knowledge:auth patterns", timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "  Searching knowledge: auth patterns"
    end

    test "formats verified verification_result" do
      event = %Event{
        type: :verification_result,
        result: "verified: users table schema",
        timestamp: DateTime.utc_now()
      }

      formatted = TrailFormatter.format(event)
      assert formatted =~ "✓ Verified: users table schema"
    end

    test "formats unverified verification_result" do
      event = %Event{
        type: :verification_result,
        result: "unverified: rate limiting",
        timestamp: DateTime.utc_now()
      }

      formatted = TrailFormatter.format(event)
      assert formatted =~ "⚠ Unverified: rate limiting"
    end

    test "formats spec_started event" do
      event = %Event{type: :spec_started, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "Generating spec..."
    end

    test "formats spec_complete event" do
      event = %Event{
        type: :spec_complete,
        result: "5 verified, 2 unverified",
        timestamp: DateTime.utc_now()
      }

      assert TrailFormatter.format(event) == "Spec complete: 5 verified, 2 unverified"
    end

    test "formats spec_complete without result" do
      event = %Event{type: :spec_complete, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "Spec complete: done"
    end

    test "truncates long paths to fit 80 columns" do
      long_path = "lib/very/deeply/nested/directory/structure/with/a/really/long/filename_that_exceeds_eighty_columns.ex"
      event = %Event{type: :file_read, path: long_path, timestamp: DateTime.utc_now()}
      formatted = TrailFormatter.format(event)

      assert String.length(formatted) <= 80
      assert String.ends_with?(formatted, "…")
    end

    test "does not truncate short paths" do
      event = %Event{type: :file_read, path: "lib/app.ex", timestamp: DateTime.utc_now()}
      formatted = TrailFormatter.format(event)

      assert formatted == "  Reading lib/app.ex"
      refute String.contains?(formatted, "…")
    end

    test "handles nil path for file_read" do
      event = %Event{type: :file_read, path: nil, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "  Reading unknown"
    end

    test "handles nil path for knowledge_search" do
      event = %Event{type: :knowledge_search, path: nil, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "  Searching knowledge: unknown"
    end

    test "handles unknown event type" do
      event = %Event{type: :custom_type, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event) == "  custom_type"
    end
  end

  describe "format/2 with hints" do
    test "appends hint for file_read" do
      event = %Event{type: :file_read, path: "lib/auth.ex", timestamp: DateTime.utc_now()}
      formatted = TrailFormatter.format(event, hint: true)
      assert formatted =~ "(checking file contents)"
    end

    test "appends hint for knowledge_search" do
      event = %Event{type: :knowledge_search, path: "knowledge:auth", timestamp: DateTime.utc_now()}
      formatted = TrailFormatter.format(event, hint: true)
      assert formatted =~ "(querying project context)"
    end

    test "appends hint for verified result" do
      event = %Event{
        type: :verification_result,
        result: "verified: table exists",
        timestamp: DateTime.utc_now()
      }

      formatted = TrailFormatter.format(event, hint: true)
      assert formatted =~ "(confirmed by file read)"
    end

    test "appends hint for unverified result" do
      event = %Event{
        type: :verification_result,
        result: "unverified: rate limiting",
        timestamp: DateTime.utc_now()
      }

      formatted = TrailFormatter.format(event, hint: true)
      assert formatted =~ "(no matching file read)"
    end

    test "no hint appended for spec_started" do
      event = %Event{type: :spec_started, timestamp: DateTime.utc_now()}
      assert TrailFormatter.format(event, hint: true) == "Generating spec..."
    end

    test "hint with long path still fits 80 columns" do
      long_path = "lib/very/deeply/nested/directory/structure/with/really/long/path.ex"
      event = %Event{type: :file_read, path: long_path, timestamp: DateTime.utc_now()}
      formatted = TrailFormatter.format(event, hint: true)
      assert String.length(formatted) <= 80
    end
  end

  describe "heartbeat/0" do
    test "returns heartbeat string" do
      result = TrailFormatter.heartbeat()
      assert result == "  ..."
      assert String.length(result) <= 80
    end
  end

  describe "property tests" do
    property "formatted output never exceeds 80 characters for any path" do
      types = [:file_read, :knowledge_search, :verification_result, :spec_started, :spec_complete]

      check all path <- path_gen(),
                type <- member_of(types) do
        result_text =
          case type do
            :verification_result -> "verified: #{path}"
            :spec_complete -> "#{:rand.uniform(10)} verified"
            _ -> nil
          end

        event = %Event{type: type, path: path, result: result_text, timestamp: DateTime.utc_now()}

        formatted = TrailFormatter.format(event)
        assert String.length(formatted) <= 80,
               "Output exceeded 80 chars (#{String.length(formatted)}): #{formatted}"

        formatted_with_hint = TrailFormatter.format(event, hint: true)
        assert String.length(formatted_with_hint) <= 80,
               "Output with hint exceeded 80 chars (#{String.length(formatted_with_hint)}): #{formatted_with_hint}"
      end
    end

    defp path_gen do
      gen all segments <- list_of(string(:alphanumeric, min_length: 1, max_length: 30), min_length: 1, max_length: 8),
              ext <- member_of(["ex", "exs", "sql", "json", "go", "ts"]) do
        Enum.join(segments, "/") <> ".#{ext}"
      end
    end
  end
end
