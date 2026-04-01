defmodule Familiar.ErrorTest do
  use ExUnit.Case, async: true

  alias Familiar.Error

  describe "recoverable?/1" do
    test "provider_unavailable is recoverable" do
      assert Error.recoverable?({:provider_unavailable, %{provider: :ollama}})
    end

    test "validation_failed is recoverable" do
      assert Error.recoverable?({:validation_failed, %{step: :lint}})
    end

    test "file_conflict is not recoverable" do
      refute Error.recoverable?({:file_conflict, %{path: "handler/auth.go"}})
    end

    test "not_found is not recoverable" do
      refute Error.recoverable?({:not_found, %{resource: :task, id: 42}})
    end

    test "invalid_config is not recoverable" do
      refute Error.recoverable?({:invalid_config, %{field: :provider}})
    end

    test "storage_failed is not recoverable" do
      refute Error.recoverable?({:storage_failed, %{reason: :dimension_mismatch}})
    end

    test "query_failed is not recoverable" do
      refute Error.recoverable?({:query_failed, %{reason: :sqlite_error}})
    end

    test "unknown error types default to not recoverable" do
      refute Error.recoverable?({:something_unexpected, %{}})
    end
  end
end
