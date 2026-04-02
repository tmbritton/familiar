defmodule Familiar.Providers.OllamaAdapterTest do
  use ExUnit.Case, async: true

  alias Familiar.Providers.OllamaAdapter

  describe "parse_ndjson/2" do
    test "parses complete NDJSON lines" do
      input = ~s({"done":false,"message":{"content":"hi"}}\n{"done":true}\n)

      {events, remainder} = OllamaAdapter.parse_ndjson("", input)

      assert length(events) == 2
      assert hd(events)["message"]["content"] == "hi"
      assert remainder == ""
    end

    test "handles partial lines with buffering" do
      partial = ~S({"done":false,"message":{"content":"he)

      {events, remainder} = OllamaAdapter.parse_ndjson("", partial)

      assert events == []
      assert remainder == partial

      {events2, remainder2} = OllamaAdapter.parse_ndjson(remainder, ~S(llo"}}) <> "\n")

      assert length(events2) == 1
      assert hd(events2)["message"]["content"] == "hello"
      assert remainder2 == ""
    end

    test "handles multiple lines in one chunk" do
      chunk =
        ~s({"done":false,"message":{"content":"a"}}\n) <>
          ~s({"done":false,"message":{"content":"b"}}\n) <>
          ~s({"done":true,"message":{"content":""}}\n)

      {events, remainder} = OllamaAdapter.parse_ndjson("", chunk)

      assert length(events) == 3
      assert remainder == ""
    end

    test "ignores empty lines" do
      {events, _} = OllamaAdapter.parse_ndjson("", ~s(\n\n{"done":true}\n\n))
      assert length(events) == 1
    end
  end

  describe "normalize_event/1" do
    test "normalizes text delta event" do
      event = %{"done" => false, "message" => %{"content" => "Hello"}}
      assert {:text_delta, "Hello"} = OllamaAdapter.normalize_event(event)
    end

    test "normalizes done event with usage" do
      event = %{
        "done" => true,
        "message" => %{"content" => "Full response"},
        "prompt_eval_count" => 10,
        "eval_count" => 25
      }

      assert {:done, payload} = OllamaAdapter.normalize_event(event)
      assert payload.content == "Full response"
      assert payload.tool_calls == []
      assert payload.usage.prompt_tokens == 10
      assert payload.usage.completion_tokens == 25
    end

    test "normalizes done event with tool calls" do
      event = %{
        "done" => true,
        "message" => %{
          "content" => "",
          "tool_calls" => [
            %{"function" => %{"name" => "get_weather", "arguments" => %{"city" => "Paris"}}}
          ]
        },
        "prompt_eval_count" => 5,
        "eval_count" => 3
      }

      assert {:done, payload} = OllamaAdapter.normalize_event(event)
      assert length(payload.tool_calls) == 1
    end

    test "normalizes done event with nil tool_calls" do
      event = %{"done" => true, "message" => %{"content" => "ok", "tool_calls" => nil}}

      assert {:done, payload} = OllamaAdapter.normalize_event(event)
      assert payload.tool_calls == []
    end

    test "normalizes unknown event as empty text delta" do
      assert {:text_delta, ""} = OllamaAdapter.normalize_event(%{"unexpected" => true})
    end
  end
end
