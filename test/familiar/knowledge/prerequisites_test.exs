defmodule Familiar.Knowledge.PrerequisitesTest do
  use ExUnit.Case, async: true

  alias Familiar.Knowledge.Prerequisites

  describe "check/1" do
    test "returns ok when all prerequisites pass" do
      check_fn = fn ->
        {:ok,
         %{
           base_url: "http://localhost:11434",
           chat_model: "llama3.2",
           embedding_model: "nomic-embed-text"
         }}
      end

      assert {:ok, _} = Prerequisites.check(check_prerequisites_fn: check_fn)
    end

    test "returns error with missing models" do
      check_fn = fn ->
        {:error,
         {:provider_unavailable,
          %{provider: :ollama, reason: :models_missing, missing: ["llama3.2", "nomic-embed-text"]}}}
      end

      result = Prerequisites.check(check_prerequisites_fn: check_fn)
      assert {:error, {:prerequisites_failed, details}} = result
      assert "llama3.2" in details.missing
      assert is_binary(details.instructions)
    end

    test "returns error when ollama unreachable" do
      check_fn = fn ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}
      end

      result = Prerequisites.check(check_prerequisites_fn: check_fn)
      assert {:error, {:prerequisites_failed, details}} = result
      assert details.instructions =~ "Ollama"
    end

    test "returns error when single model missing" do
      check_fn = fn ->
        {:error,
         {:provider_unavailable,
          %{provider: :ollama, reason: :model_not_found, model: "nomic-embed-text"}}}
      end

      result = Prerequisites.check(check_prerequisites_fn: check_fn)
      assert {:error, {:prerequisites_failed, details}} = result
      assert "nomic-embed-text" in details.missing
    end
  end
end
