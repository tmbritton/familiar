defmodule Familiar.CLI.OutputTest do
  use ExUnit.Case, async: true

  alias Familiar.CLI.Output

  describe "format/3 with :json mode" do
    test "wraps success data in data envelope" do
      result = Output.format({:ok, %{status: "ok"}}, :json)
      decoded = Jason.decode!(result)
      assert decoded == %{"data" => %{"status" => "ok"}}
    end

    test "wraps list data in data envelope" do
      result = Output.format({:ok, [1, 2, 3]}, :json)
      decoded = Jason.decode!(result)
      assert decoded == %{"data" => [1, 2, 3]}
    end

    test "wraps string data in data envelope" do
      result = Output.format({:ok, "hello"}, :json)
      decoded = Jason.decode!(result)
      assert decoded == %{"data" => "hello"}
    end

    test "wraps error in error envelope with human-readable message" do
      result = Output.format({:error, {:daemon_unavailable, %{}}}, :json)
      decoded = Jason.decode!(result)

      assert decoded["error"]["type"] == "daemon_unavailable"
      assert decoded["error"]["message"] =~ "not running"
      assert decoded["error"]["details"] == %{}
    end

    test "includes error details in envelope" do
      result =
        Output.format(
          {:error, {:version_mismatch, %{cli: "1.0.0", daemon: "2.0.0"}}},
          :json
        )

      decoded = Jason.decode!(result)
      assert decoded["error"]["type"] == "version_mismatch"
      assert decoded["error"]["details"]["cli"] == "1.0.0"
      assert decoded["error"]["details"]["daemon"] == "2.0.0"
    end

    test "uses snake_case field names" do
      result = Output.format({:ok, %{some_field: "value"}}, :json)
      decoded = Jason.decode!(result)
      assert Map.has_key?(decoded["data"], "some_field")
    end
  end

  describe "format/3 with :text mode" do
    test "uses default inspect formatter for success" do
      result = Output.format({:ok, %{status: "ok"}}, :text)
      assert result =~ "status"
      assert result =~ "ok"
    end

    test "uses custom formatter when provided" do
      formatter = fn %{status: status} -> "Status: #{status}" end
      result = Output.format({:ok, %{status: "ok"}}, :text, formatter)
      assert result == "Status: ok"
    end

    test "formats errors with type and message" do
      result = Output.format({:error, {:daemon_unavailable, %{}}}, :text)
      assert result =~ "Error"
      assert result =~ "daemon_unavailable"
    end
  end

  describe "format/3 with :quiet mode" do
    test "returns minimal success output" do
      result = Output.format({:ok, %{status: "ok"}}, :quiet)
      assert result == "ok"
    end

    test "returns error type for errors" do
      result = Output.format({:error, {:daemon_unavailable, %{}}}, :quiet)
      assert result == "error: daemon_unavailable"
    end
  end

  describe "format/3 — invalid_config error" do
    test "JSON envelope for invalid_config includes field and reason" do
      result =
        Output.format(
          {:error,
           {:invalid_config, %{field: "provider.timeout", reason: "expected positive integer"}}},
          :json
        )

      decoded = Jason.decode!(result)
      assert decoded["error"]["type"] == "invalid_config"
      assert decoded["error"]["message"] =~ "provider.timeout"
      assert decoded["error"]["details"]["field"] == "provider.timeout"
    end

    test "text mode for invalid_config shows error type" do
      result =
        Output.format(
          {:error, {:invalid_config, %{field: "scan.max_files", reason: "must be positive"}}},
          :text
        )

      assert result =~ "invalid_config"
    end

    test "quiet mode for invalid_config returns error type" do
      result =
        Output.format(
          {:error, {:invalid_config, %{field: "x", reason: "y"}}},
          :quiet
        )

      assert result == "error: invalid_config"
    end
  end

  describe "JSON envelope contract for all error types" do
    test "all known error types produce valid JSON with type, message, details" do
      error_cases = [
        {:daemon_unavailable, %{}},
        {:timeout, %{}},
        {:version_mismatch, %{cli: "0.1.0", daemon: "0.2.0"}},
        {:init_required, %{}},
        {:prerequisites_failed, %{instructions: "Install Ollama"}},
        {:already_initialized, %{path: ".familiar/"}},
        {:init_failed, %{reason: "boom"}},
        {:unknown_command, %{command: "bogus"}},
        {:usage_error, %{message: "bad usage"}},
        {:invalid_config, %{field: "provider.timeout", reason: "expected positive integer"}}
      ]

      for {type, details} <- error_cases do
        result = Output.format({:error, {type, details}}, :json)
        decoded = Jason.decode!(result)
        assert is_map(decoded["error"]), "Missing error envelope for #{type}"
        assert decoded["error"]["type"] == to_string(type), "Wrong type for #{type}"
        assert is_binary(decoded["error"]["message"]), "Missing message for #{type}"
        assert is_map(decoded["error"]["details"]), "Missing details for #{type}"
      end
    end
  end

  describe "Story 7.5-6 resume error messages" do
    test ":no_resumable_workflow JSON message mentions list-runs" do
      result = Output.format({:error, {:no_resumable_workflow, %{}}}, :json)
      data = Jason.decode!(result)
      assert data["error"]["type"] == "no_resumable_workflow"
      assert data["error"]["message"] =~ "No resumable workflow runs"
      assert data["error"]["message"] =~ "fam workflows list-runs"
    end

    test ":workflow_run_not_found JSON message includes the id" do
      result = Output.format({:error, {:workflow_run_not_found, %{id: 42}}}, :json)
      data = Jason.decode!(result)
      assert data["error"]["message"] =~ "##{42}"
      assert data["error"]["message"] =~ "fam workflows list-runs"
    end

    test ":workflow_already_completed JSON message includes the id" do
      result = Output.format({:error, {:workflow_already_completed, %{id: 7}}}, :json)
      data = Jason.decode!(result)
      assert data["error"]["message"] =~ "##{7}"
      assert data["error"]["message"] =~ "already completed"
    end

    test ":workflow_path_missing JSON message explains the run_workflow_parsed gotcha" do
      result = Output.format({:error, {:workflow_path_missing, %{id: 9}}}, :json)
      data = Jason.decode!(result)
      assert data["error"]["message"] =~ "##{9}"
      assert data["error"]["message"] =~ "run_workflow_parsed"
    end

    test ":workflow_finalize_failed text message includes the reason" do
      # Use :text mode — the details map may contain non-JSON-serializable
      # terms like tuples, which the error_message/2 `inspect/2` call handles
      # fine. JSON mode would fail to encode the raw details tuple.
      result =
        Output.format(
          {:error, {:workflow_finalize_failed, %{id: 5, reason: {:constraint_error, "fk"}}}},
          :text
        )

      assert result =~ "##{5}"
      assert result =~ "stuck past its final step"
      assert result =~ "constraint_error"
    end
  end

  describe "exit_code/1" do
    test "returns 0 for success" do
      assert Output.exit_code({:ok, _any = nil}) == 0
    end

    test "returns 1 for errors" do
      assert Output.exit_code({:error, {:daemon_unavailable, %{}}}) == 1
    end

    test "returns 1 for invalid_config" do
      assert Output.exit_code({:error, {:invalid_config, %{}}}) == 1
    end

    test "returns 2 for usage errors" do
      assert Output.exit_code({:error, {:unknown_command, %{}}}) == 2
      assert Output.exit_code({:error, {:usage_error, %{}}}) == 2
    end
  end
end
