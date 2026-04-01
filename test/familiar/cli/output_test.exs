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

  describe "exit_code/1" do
    test "returns 0 for success" do
      assert Output.exit_code({:ok, _any = nil}) == 0
    end

    test "returns 1 for errors" do
      assert Output.exit_code({:error, {:daemon_unavailable, %{}}}) == 1
    end

    test "returns 2 for usage errors" do
      assert Output.exit_code({:error, {:unknown_command, %{}}}) == 2
      assert Output.exit_code({:error, {:usage_error, %{}}}) == 2
    end
  end
end
