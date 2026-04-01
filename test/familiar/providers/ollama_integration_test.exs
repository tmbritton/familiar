defmodule Familiar.Providers.OllamaIntegrationTest do
  @moduledoc """
  Integration tests that require a running Ollama instance.

  Excluded by default. Run with: mix test --include integration
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Familiar.Providers.Detector
  alias Familiar.Providers.OllamaAdapter
  alias Familiar.Providers.OllamaEmbedder

  describe "Detector" do
    test "detect/0 finds running Ollama" do
      assert {:ok, url} = Detector.detect()
      assert String.starts_with?(url, "http")
    end

    test "list_models/0 returns installed models" do
      assert {:ok, models} = Detector.list_models()
      assert is_list(models)
      assert models != []
    end

    test "check_prerequisites/0 validates required models" do
      assert {:ok, result} = Detector.check_prerequisites()
      assert is_binary(result.base_url)
      assert is_binary(result.chat_model)
      assert is_binary(result.embedding_model)
    end
  end

  describe "OllamaAdapter" do
    test "chat/2 returns a complete response" do
      messages = [%{role: "user", content: "Say hello in exactly one word."}]
      assert {:ok, response} = OllamaAdapter.chat(messages)
      assert is_binary(response.content)
      assert response.content != ""
      assert is_list(response.tool_calls)
      assert is_map(response.usage)
    end

    test "stream_chat/2 returns a stream of events" do
      messages = [%{role: "user", content: "Count from 1 to 3."}]
      assert {:ok, stream} = OllamaAdapter.stream_chat(messages)

      events = Enum.to_list(stream)
      assert events != []

      # Should end with a :done event
      last = List.last(events)
      assert match?({:done, _}, last)

      # Should have at least one :text_delta
      text_deltas = Enum.filter(events, &match?({:text_delta, _}, &1))
      assert text_deltas != []
    end
  end

  describe "OllamaEmbedder" do
    test "embed/1 returns a float vector" do
      assert {:ok, vector} = OllamaEmbedder.embed("Hello world")
      assert is_list(vector)
      assert vector != []
      assert Enum.all?(vector, &is_float/1)
    end
  end
end
