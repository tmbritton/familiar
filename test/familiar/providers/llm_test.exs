defmodule Familiar.Providers.LLMTest do
  use Familiar.MockCase

  alias Familiar.Providers.LLMMock

  describe "LLM behaviour mock" do
    test "chat/2 can be mocked with a scripted response" do
      expect(LLMMock, :chat, fn messages, _opts ->
        assert [%{role: "user", content: "hello"}] = messages
        {:ok, %{content: "Hi there!", tool_calls: [], usage: %{}}}
      end)

      assert {:ok, %{content: "Hi there!"}} =
               LLMMock.chat([%{role: "user", content: "hello"}], [])
    end

    test "stream_chat/2 can be mocked" do
      expect(LLMMock, :stream_chat, fn _messages, _opts ->
        {:ok, Stream.map(["chunk1", "chunk2"], &{:text_delta, &1})}
      end)

      assert {:ok, stream} = LLMMock.stream_chat([%{role: "user", content: "hello"}], [])
      events = Enum.to_list(stream)
      assert [{:text_delta, "chunk1"}, {:text_delta, "chunk2"}] = events
    end

    test "chat/2 can return error tuples" do
      expect(LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}
      end)

      assert {:error, {:provider_unavailable, _}} = LLMMock.chat([], [])
    end
  end
end
