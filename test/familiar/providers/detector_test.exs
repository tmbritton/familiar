defmodule Familiar.Providers.DetectorTest do
  use ExUnit.Case, async: true

  alias Familiar.Providers.Detector

  describe "has_model?/2" do
    test "matches exact model name" do
      assert Detector.has_model?(["llama3.2"], "llama3.2")
    end

    test "matches model name with :tag suffix" do
      assert Detector.has_model?(["llama3.2:latest"], "llama3.2")
    end

    test "does not match partial prefix" do
      refute Detector.has_model?(["llama3.2:latest"], "llama3")
    end

    test "does not match when model is not in list" do
      refute Detector.has_model?(["mistral:latest"], "llama3.2")
    end

    test "matches in list of multiple models" do
      models = ["mistral:latest", "llama3.2:latest", "nomic-embed-text:latest"]
      assert Detector.has_model?(models, "nomic-embed-text")
    end

    test "returns false for empty model list" do
      refute Detector.has_model?([], "llama3.2")
    end
  end

  describe "detect/0" do
    @tag :integration
    test "detects running Ollama or returns connection error" do
      case Detector.detect() do
        {:ok, url} -> assert is_binary(url)
        {:error, {:provider_unavailable, _}} -> :ok
      end
    end
  end

  describe "list_models/0" do
    @tag :integration
    test "lists models or returns connection error" do
      case Detector.list_models() do
        {:ok, models} -> assert is_list(models)
        {:error, {:provider_unavailable, _}} -> :ok
      end
    end
  end

  describe "check_prerequisites/0" do
    @tag :integration
    test "validates required models or returns specific error" do
      case Detector.check_prerequisites() do
        {:ok, result} ->
          assert is_binary(result.base_url)
          assert is_binary(result.chat_model)
          assert is_binary(result.embedding_model)

        {:error, {:provider_unavailable, details}} ->
          assert is_atom(details.reason)
      end
    end
  end
end
