defmodule Familiar.Providers.ProvidersTest do
  use Familiar.MockCase

  alias Familiar.Knowledge.EmbedderMock
  alias Familiar.Providers
  alias Familiar.Providers.LLMMock

  describe "chat/2" do
    test "delegates to configured LLM adapter" do
      messages = [%{role: "user", content: "hello"}]

      expect(LLMMock, :chat, fn msgs, _opts ->
        assert msgs == messages
        {:ok, %{content: "Hi!", tool_calls: [], usage: %{}}}
      end)

      assert {:ok, %{content: "Hi!"}} = Providers.chat(messages)
    end

    test "passes opts through to adapter" do
      expect(LLMMock, :chat, fn _msgs, opts ->
        assert opts[:model] == "custom-model"
        {:ok, %{content: "ok", tool_calls: [], usage: %{}}}
      end)

      assert {:ok, _} = Providers.chat([%{role: "user", content: "hi"}], model: "custom-model")
    end

    test "returns error tuple from adapter" do
      expect(LLMMock, :chat, fn _msgs, _opts ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}
      end)

      assert {:error, {:provider_unavailable, _}} =
               Providers.chat([%{role: "user", content: "hi"}])
    end
  end

  describe "stream_chat/2" do
    test "delegates to configured LLM adapter" do
      expect(LLMMock, :stream_chat, fn msgs, _opts ->
        assert length(msgs) == 1
        {:ok, Stream.map([], & &1)}
      end)

      assert {:ok, stream} = Providers.stream_chat([%{role: "user", content: "hi"}])
      assert is_function(stream) or is_struct(stream, Stream)
    end
  end

  describe "embed/1" do
    test "delegates to configured Embedder adapter" do
      vector = List.duplicate(0.5, 768)

      expect(EmbedderMock, :embed, fn text ->
        assert text == "test input"
        {:ok, vector}
      end)

      assert {:ok, ^vector} = Providers.embed("test input")
    end

    test "returns error tuple from adapter" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}
      end)

      assert {:error, {:provider_unavailable, _}} = Providers.embed("test")
    end
  end
end
