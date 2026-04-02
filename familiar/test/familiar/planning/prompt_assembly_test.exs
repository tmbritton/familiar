defmodule Familiar.Planning.PromptAssemblyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Familiar.Planning.PromptAssembly

  describe "assemble/2" do
    test "returns system prompt and messages tuple" do
      {system, messages} = PromptAssembly.assemble(nil)

      assert is_binary(system)
      assert is_list(messages)
    end

    test "system prompt contains adaptive depth instructions" do
      {system, _messages} = PromptAssembly.assemble(nil)

      assert String.contains?(system, "Adaptive depth")
      assert String.contains?(system, "3-5")
      assert String.contains?(system, "0-2")
    end

    test "system prompt contains no-repeat instruction" do
      {system, _messages} = PromptAssembly.assemble(nil)

      assert String.contains?(system, "Never repeat questions")
    end

    test "system prompt contains citation instruction" do
      {system, _messages} = PromptAssembly.assemble(nil)

      assert String.contains?(system, "cite the source")
    end

    test "system prompt contains spec-ready signal instruction" do
      {system, _messages} = PromptAssembly.assemble(nil)

      assert String.contains?(system, "[SPEC_READY]")
    end

    test "with no history, messages contain only system message" do
      {_system, messages} = PromptAssembly.assemble(nil)

      assert [%{role: "system"}] = messages
    end

    test "with history, messages are system + history" do
      history = [
        %{role: "user", content: "add auth"},
        %{role: "assistant", content: "What method?"}
      ]

      {_system, messages} = PromptAssembly.assemble(nil, history)

      assert length(messages) == 3
      assert Enum.at(messages, 0).role == "system"
      assert Enum.at(messages, 1).role == "user"
      assert Enum.at(messages, 1).content == "add auth"
      assert Enum.at(messages, 2).role == "assistant"
    end

    test "includes context block in system prompt when provided" do
      context = "Users table has email column [db/migrations/001.sql]"
      {system, _messages} = PromptAssembly.assemble(context)

      assert String.contains?(system, "Project Context")
      assert String.contains?(system, "Users table has email column")
    end

    test "omits context section when context is nil" do
      {system, _messages} = PromptAssembly.assemble(nil)

      refute String.contains?(system, "Project Context")
    end

    test "omits context section when context is empty string" do
      {system, _messages} = PromptAssembly.assemble("")

      refute String.contains?(system, "Project Context")
    end

    test "handles empty conversation history" do
      {_system, messages} = PromptAssembly.assemble(nil, [])

      assert [%{role: "system"}] = messages
    end

    test "normalizes string-keyed history maps" do
      history = [
        %{"role" => "user", "content" => "question?"}
      ]

      {_system, messages} = PromptAssembly.assemble(nil, history)

      assert Enum.at(messages, 1).role == "user"
      assert Enum.at(messages, 1).content == "question?"
    end
  end

  describe "system_prompt_template/0" do
    test "returns a non-empty string" do
      template = PromptAssembly.system_prompt_template()
      assert is_binary(template)
      assert String.length(template) > 100
    end
  end

  describe "property tests" do
    property "assemble always returns {binary, list} for any context" do
      check all context <- one_of([constant(nil), string(:printable, min_length: 1)]) do
        {system, messages} = PromptAssembly.assemble(context)

        assert is_binary(system)
        assert is_list(messages)
        assert [%{role: "system"} | _] = messages
      end
    end

    property "assemble with context always includes context in system prompt" do
      check all context <- string(:printable, min_length: 1) do
        {system, _messages} = PromptAssembly.assemble(context)

        assert String.contains?(system, context)
        assert String.contains?(system, "Project Context")
      end
    end

    property "message count equals 1 + history length" do
      check all history_len <- integer(0..10) do
        history =
          if history_len == 0 do
            []
          else
            Enum.map(1..history_len, fn i ->
              role = if rem(i, 2) == 1, do: "user", else: "assistant"
              %{role: role, content: "message #{i}"}
            end)
          end

        {_system, messages} = PromptAssembly.assemble(nil, history)

        assert length(messages) == 1 + history_len
      end
    end

    property "system prompt always contains core instructions regardless of inputs" do
      check all context <- one_of([constant(nil), string(:printable, min_length: 1)]) do
        {system, _messages} = PromptAssembly.assemble(context)

        assert String.contains?(system, "Adaptive depth")
        assert String.contains?(system, "[SPEC_READY]")
        assert String.contains?(system, "Never repeat")
      end
    end
  end
end
