defmodule Familiar.Execution.PromptAssemblyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Familiar.Execution.PromptAssembly
  alias Familiar.Roles.{Role, Skill}

  # -- Helpers --

  defp make_role(attrs \\ %{}) do
    %Role{
      name: Map.get(attrs, :name, "coder"),
      description: Map.get(attrs, :description, "A coding agent"),
      system_prompt: Map.get(attrs, :system_prompt, "You are a coder."),
      model: Map.get(attrs, :model, "llama3.2"),
      skills: Map.get(attrs, :skills, [])
    }
  end

  defp make_skill(attrs \\ %{}) do
    %Skill{
      name: Map.get(attrs, :name, "implement"),
      description: Map.get(attrs, :description, "Implementation skill"),
      tools: Map.get(attrs, :tools, ["read_file", "write_file"]),
      instructions: Map.get(attrs, :instructions, "When implementing, follow TDD.")
    }
  end

  defp make_params(overrides \\ %{}) do
    Map.merge(
      %{
        role: make_role(),
        skills: [],
        task: "Implement auth handler",
        messages: []
      },
      overrides
    )
  end

  # == Task 1: Core Assembly (AC1, AC2) ==

  describe "assemble/2 — basic assembly" do
    test "returns messages, tools, and metadata 3-tuple" do
      {messages, tools, metadata} = PromptAssembly.assemble(make_params())

      assert is_list(messages)
      assert is_list(tools)
      assert is_map(metadata)
      assert Map.has_key?(metadata, :truncated)
      assert Map.has_key?(metadata, :context_truncated)
      assert Map.has_key?(metadata, :dropped_entries)
      assert Map.has_key?(metadata, :token_budget)
    end

    test "message ordering: system first, user second, then history" do
      history = [
        %{role: "assistant", content: "I'll check the file."},
        %{role: "tool", content: ~s({"ok": "file contents"})}
      ]

      {messages, _tools, _meta} = PromptAssembly.assemble(make_params(%{messages: history}))

      assert [system, user, assistant, tool] = messages
      assert system.role == "system"
      assert user.role == "user"
      assert assistant.role == "assistant"
      assert tool.role == "tool"
    end

    test "system message combines role prompt and skill instructions" do
      skill1 = make_skill(%{instructions: "Skill one instructions."})
      skill2 = make_skill(%{name: "test", instructions: "Skill two instructions."})

      {[system | _], _tools, _meta} =
        PromptAssembly.assemble(make_params(%{skills: [skill1, skill2]}))

      assert system.content =~ "You are a coder."
      assert system.content =~ "Skill one instructions."
      assert system.content =~ "Skill two instructions."
    end

    test "multiple skills concatenated with double newlines" do
      skill1 = make_skill(%{instructions: "AAA"})
      skill2 = make_skill(%{name: "s2", instructions: "BBB"})

      {[system | _], _tools, _meta} =
        PromptAssembly.assemble(make_params(%{skills: [skill1, skill2]}))

      assert system.content =~ "AAA\n\nBBB"
    end

    test "user message contains the task" do
      {[_sys, user | _], _tools, _meta} =
        PromptAssembly.assemble(make_params(%{task: "Build the widget"}))

      assert user.content == "Build the widget"
    end

    test "nil system_prompt uses empty string" do
      role = make_role(%{system_prompt: nil})
      {[system | _], _tools, _meta} = PromptAssembly.assemble(make_params(%{role: role}))
      assert is_binary(system.content)
    end

    test "nil skill instructions are filtered out" do
      skill_with_nil = %Skill{
        name: "empty",
        description: "No instructions",
        tools: [],
        instructions: nil
      }

      skill_with_text = make_skill(%{instructions: "Real instructions."})

      {[system | _], _tools, _meta} =
        PromptAssembly.assemble(make_params(%{skills: [skill_with_nil, skill_with_text]}))

      assert system.content =~ "Real instructions."
      refute system.content =~ "nil"
    end

    test "empty skills list uses only role prompt" do
      {[system | _], _tools, _meta} = PromptAssembly.assemble(make_params(%{skills: []}))
      assert system.content == "You are a coder."
    end

    test "tools returned from skills" do
      skill = make_skill(%{tools: ["read_file", "write_file"]})
      {_msgs, tools, _meta} = PromptAssembly.assemble(make_params(%{skills: [skill]}))
      assert "read_file" in tools
      assert "write_file" in tools
    end
  end

  # == Task 2: Token Estimation (AC4) ==

  describe "estimate_tokens/1" do
    test "estimates tokens for a string using chars/4 heuristic" do
      assert PromptAssembly.estimate_tokens("12345678901234567890") == 5
    end

    test "rounds up for non-divisible lengths" do
      assert PromptAssembly.estimate_tokens("hello") == 2
    end

    test "empty string returns 0" do
      assert PromptAssembly.estimate_tokens("") == 0
    end

    test "estimates tokens for a list of messages" do
      messages = [
        %{role: "system", content: "12345678"},
        %{role: "user", content: "1234"}
      ]

      assert PromptAssembly.estimate_tokens(messages) == 3
    end

    test "handles messages with string keys" do
      messages = [
        %{"role" => "system", "content" => "12345678"}
      ]

      assert PromptAssembly.estimate_tokens(messages) == 2
    end
  end

  # == Task 3: Token Budget and Truncation (AC3) ==

  describe "assemble/2 — token budget" do
    test "under budget returns truncated: false with empty dropped_entries" do
      {_msgs, _tools, meta} = PromptAssembly.assemble(make_params(), token_budget: 128_000)

      assert meta.truncated == false
      assert meta.dropped_entries == []
    end

    test "over budget truncates history from oldest, preserving system+task" do
      large_msg = String.duplicate("x", 400)

      history =
        Enum.map(0..9, fn i ->
          %{role: "assistant", content: "msg#{i}: #{large_msg}"}
        end)

      {messages, _tools, meta} =
        PromptAssembly.assemble(make_params(%{messages: history}), token_budget: 200)

      assert meta.truncated == true
      assert meta.dropped_entries != []

      assert hd(messages).role == "system"
      assert Enum.at(messages, 1).role == "user"

      assert length(messages) < length(history) + 2

      # History portion fits within remaining budget
      fixed = estimate_fixed(messages)
      history_after = meta.token_budget.after_truncation - fixed
      remaining = max(meta.token_budget.limit - fixed, 0)
      assert history_after <= remaining
    end

    test "system and task messages are never truncated even if they exceed budget" do
      role = make_role(%{system_prompt: String.duplicate("y", 1000)})

      {messages, _tools, meta} =
        PromptAssembly.assemble(make_params(%{role: role}), token_budget: 10)

      assert length(messages) >= 2
      assert hd(messages).role == "system"
      assert Enum.at(messages, 1).role == "user"
      assert meta.token_budget.after_truncation > meta.token_budget.limit
    end

    test "metadata reports limit, estimated, and after_truncation" do
      {_msgs, _tools, meta} = PromptAssembly.assemble(make_params(), token_budget: 50_000)

      assert is_integer(meta.token_budget.limit)
      assert meta.token_budget.limit == 50_000
      assert is_integer(meta.token_budget.estimated)
      assert is_integer(meta.token_budget.after_truncation)
    end

    test "dropped_entries lists indices of removed messages" do
      history =
        Enum.map(0..4, fn i ->
          %{role: "assistant", content: String.duplicate("x", 400) <> " msg#{i}"}
        end)

      {_messages, _tools, meta} =
        PromptAssembly.assemble(make_params(%{messages: history}), token_budget: 150)

      assert Enum.all?(meta.dropped_entries, fn idx -> idx >= 0 and idx < 5 end)
      assert meta.dropped_entries == Enum.sort(meta.dropped_entries)
    end

    test "default token budget is 128_000" do
      {_msgs, _tools, meta} = PromptAssembly.assemble(make_params())
      assert meta.token_budget.limit == 128_000
    end

    test "keeps newest messages when truncating, not oldest" do
      # 4 messages: old_small, old_big, new_small, newest_small
      history = [
        %{role: "assistant", content: String.duplicate("a", 40)},
        %{role: "assistant", content: String.duplicate("b", 400)},
        %{role: "assistant", content: String.duplicate("c", 40)},
        %{role: "assistant", content: String.duplicate("d", 40)}
      ]

      # Budget allows system+task (~25 tokens) + ~40 tokens of history
      {messages, _tools, meta} =
        PromptAssembly.assemble(make_params(%{messages: history}), token_budget: 65)

      assert meta.truncated == true
      # Should keep the newest messages that fit, dropping oldest/largest
      # The big message (index 1) should be dropped
      assert 1 in meta.dropped_entries
    end
  end

  # == Task 4: Context Block Injection (AC5) ==

  describe "assemble/2 — context injection" do
    test "context appended to system message with separator" do
      {[system | _], _tools, _meta} =
        PromptAssembly.assemble(make_params(), context: "Project uses Phoenix 1.7")

      assert system.content =~ "You are a coder."
      assert system.content =~ "\n\n---\n\n"
      assert system.content =~ "Project uses Phoenix 1.7"
    end

    test "nil context does not add separator" do
      {[system | _], _tools, _meta} = PromptAssembly.assemble(make_params(), context: nil)

      refute system.content =~ "---"
    end

    test "empty string context does not add separator" do
      {[system | _], _tools, _meta} = PromptAssembly.assemble(make_params(), context: "")

      refute system.content =~ "---"
    end

    test "oversized context is truncated with marker" do
      huge_context = String.duplicate("z", 100_000)

      {[system | _], _tools, meta} =
        PromptAssembly.assemble(make_params(), context: huge_context, token_budget: 500)

      assert system.content =~ "[context truncated]"
      assert meta.context_truncated == true
    end

    test "context truncation reflected in metadata" do
      huge_context = String.duplicate("z", 100_000)

      {_msgs, _tools, meta} =
        PromptAssembly.assemble(make_params(), context: huge_context, token_budget: 500)

      assert meta.context_truncated == true
    end

    test "non-truncated context has context_truncated: false" do
      {_msgs, _tools, meta} =
        PromptAssembly.assemble(make_params(), context: "small context")

      assert meta.context_truncated == false
    end

    test "nil context has context_truncated: false" do
      {_msgs, _tools, meta} = PromptAssembly.assemble(make_params(), context: nil)
      assert meta.context_truncated == false
    end
  end

  # == Task 5: Tool Definitions (AC6) ==

  describe "tool_definitions/1" do
    test "extracts tool names from skills" do
      skills = [
        make_skill(%{tools: ["read_file", "write_file"]}),
        make_skill(%{name: "test", tools: ["run_command"]})
      ]

      tools = PromptAssembly.tool_definitions(skills)
      assert "read_file" in tools
      assert "write_file" in tools
      assert "run_command" in tools
    end

    test "deduplicates tool names across skills" do
      skills = [
        make_skill(%{tools: ["read_file", "write_file"]}),
        make_skill(%{name: "review", tools: ["read_file", "search_files"]})
      ]

      tools = PromptAssembly.tool_definitions(skills)
      assert length(Enum.filter(tools, &(&1 == "read_file"))) == 1
    end

    test "returns empty list for no skills" do
      assert PromptAssembly.tool_definitions([]) == []
    end

    test "handles skills with nil tools" do
      skill = %Skill{
        name: "empty",
        description: "No tools",
        tools: nil,
        instructions: "Do nothing"
      }

      assert PromptAssembly.tool_definitions([skill]) == []
    end
  end

  # == Property-based tests (AC8) ==

  describe "property: output never exceeds token budget" do
    property "history portion fits within remaining budget for any valid inputs" do
      check all(
              prompt_len <- StreamData.integer(0..500),
              task_len <- StreamData.integer(1..200),
              history_count <- StreamData.integer(0..20),
              msg_len <- StreamData.integer(1..200),
              budget <- StreamData.integer(50..10_000)
            ) do
        role =
          make_role(%{
            system_prompt: String.duplicate("a", prompt_len)
          })

        history =
          if history_count == 0 do
            []
          else
            Enum.map(1..history_count, fn _ ->
              %{role: "assistant", content: String.duplicate("b", msg_len)}
            end)
          end

        params = %{
          role: role,
          skills: [],
          task: String.duplicate("c", task_len),
          messages: history
        }

        {messages, _tools, meta} = PromptAssembly.assemble(params, token_budget: budget)

        history_msgs = Enum.drop(messages, 2)
        history_tokens = PromptAssembly.estimate_tokens(history_msgs)
        fixed_tokens = meta.token_budget.after_truncation - history_tokens
        remaining_budget = max(budget - fixed_tokens, 0)

        # Core invariant: history tokens never exceed remaining budget
        assert history_tokens <= remaining_budget

        # If truncation happened, after_truncation <= estimated
        if meta.truncated do
          assert meta.token_budget.after_truncation <= meta.token_budget.estimated
        end

        # Metadata consistency
        assert meta.token_budget.limit == budget
        assert is_list(meta.dropped_entries)
        assert is_boolean(meta.truncated)

        # System and user are always present
        assert length(messages) >= 2
        assert hd(messages).role == "system"
        assert Enum.at(messages, 1).role == "user"

        # Dropped entries + kept history = original history
        assert length(meta.dropped_entries) + length(history_msgs) == history_count
      end
    end
  end

  # == build_system_prompt/2-4 ==

  describe "build_system_prompt/4" do
    test "combines role and skills" do
      role = make_role()
      skills = [make_skill(%{instructions: "Follow TDD."})]
      result = PromptAssembly.build_system_prompt(role, skills)

      assert result == "You are a coder.\n\nFollow TDD."
    end

    test "role only when no skills" do
      result = PromptAssembly.build_system_prompt(make_role(), [])
      assert result == "You are a coder."
    end

    test "nil system_prompt with skills produces no leading newlines" do
      role = make_role(%{system_prompt: nil})
      skills = [make_skill(%{instructions: "Do TDD."})]
      result = PromptAssembly.build_system_prompt(role, skills)

      assert result == "Do TDD."
    end

    test "with context block" do
      role = make_role()
      result = PromptAssembly.build_system_prompt(role, [], "Some context")

      assert result =~ "You are a coder."
      assert result =~ "---"
      assert result =~ "Some context"
    end
  end

  # -- Private helper --

  defp estimate_fixed(messages) do
    sys = hd(messages)
    task = Enum.at(messages, 1)
    PromptAssembly.estimate_tokens(sys.content) + PromptAssembly.estimate_tokens(task.content)
  end
end
