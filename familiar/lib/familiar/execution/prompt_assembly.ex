defmodule Familiar.Execution.PromptAssembly do
  @moduledoc """
  Pure function module that assembles role prompts, skill instructions,
  context, and conversation history into LLM messages.

  This is infrastructure, not content — it assembles prompts from role
  files but does not define prompt text. All prompt content comes from
  `.familiar/roles/` and `.familiar/skills/` markdown files.

  ## Token Budget Management

  Estimates token usage with a character-based heuristic (`chars / 4`)
  and truncates conversation history from oldest messages when the
  budget is exceeded. System and user task messages are never truncated.

  ## Return Value

  `assemble/2` returns `{messages, tools, metadata}` where:

    * `messages` — list of `%{role: String.t(), content: String.t()}`
      maps ready for `Providers.chat/2`
    * `tools` — list of tool name strings extracted from skills
    * `metadata` — `%{truncated: boolean, context_truncated: boolean,
      dropped_entries: list, token_budget: %{limit: integer,
      estimated: integer, after_truncation: integer}}`
  """

  alias Familiar.Roles.{Role, Skill}

  @default_token_budget 128_000
  @context_separator "\n\n---\n\n"

  @doc """
  Assemble messages for an LLM call from role, skills, task, and history.

  ## Params

    * `params` — map with `:role` (`Role.t()`), `:skills` (list of `Skill.t()`),
      `:task` (string), `:messages` (list of prior conversation messages)

  ## Options

    * `:token_budget` — max estimated tokens (default: #{@default_token_budget})
    * `:context` — optional context block string to inject into system message
  """
  @spec assemble(map(), keyword()) :: {list(map()), [String.t()], map()}
  def assemble(params, opts \\ []) do
    role = Map.fetch!(params, :role)
    skills = Map.get(params, :skills, [])
    task = Map.fetch!(params, :task)
    history = Map.get(params, :messages, [])
    budget = Keyword.get(opts, :token_budget, @default_token_budget)
    context = Keyword.get(opts, :context)

    {system_content, context_was_truncated} =
      build_system_prompt_with_meta(role, skills, context, budget)

    system_msg = %{role: "system", content: system_content}
    task_msg = %{role: "user", content: task}

    fixed_tokens = estimate_tokens(system_content) + estimate_tokens(task)
    remaining = max(budget - fixed_tokens, 0)

    {kept_history, dropped_indices, history_tokens, full_history_tokens} =
      truncate_history(history, remaining)

    total_after = fixed_tokens + history_tokens
    truncated = dropped_indices != []

    messages = [system_msg, task_msg | kept_history]
    tools = tool_definitions(skills)

    metadata = %{
      truncated: truncated,
      context_truncated: context_was_truncated,
      dropped_entries: dropped_indices,
      token_budget: %{
        limit: budget,
        estimated: fixed_tokens + full_history_tokens,
        after_truncation: total_after
      }
    }

    {messages, tools, metadata}
  end

  @doc """
  Build the system prompt from a role and its skills.

  Combines `role.system_prompt` with skill instructions joined by
  double newlines. Optionally appends a context block.
  """
  @spec build_system_prompt(Role.t(), [Skill.t()], String.t() | nil, integer()) :: String.t()
  def build_system_prompt(%Role{} = role, skills, context \\ nil, budget \\ @default_token_budget) do
    {content, _truncated} = build_system_prompt_with_meta(role, skills, context, budget)
    content
  end

  @doc """
  Estimate the token count for a string or list of messages.

  Uses a character-based heuristic: `ceil(chars / 4)`.
  """
  @spec estimate_tokens(String.t() | [map()]) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    case String.length(text) do
      0 -> 0
      len -> ceil(len / 4)
    end
  end

  def estimate_tokens(messages) when is_list(messages) do
    estimate_tokens_for_messages(messages)
  end

  @doc """
  Extract tool definitions from a list of skills.

  Returns a flat, deduplicated list of tool name strings
  referenced across all skills.
  """
  @spec tool_definitions([Skill.t()]) :: [String.t()]
  def tool_definitions(skills) when is_list(skills) do
    skills
    |> Enum.flat_map(fn %Skill{} = skill -> skill.tools || [] end)
    |> Enum.uniq()
  end

  # -- Private --

  defp build_system_prompt_with_meta(%Role{} = role, skills, context, budget) do
    base_prompt = role.system_prompt || ""

    skill_text =
      skills
      |> Enum.map(fn %Skill{} = skill -> skill.instructions end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    combined =
      case skill_text do
        "" -> base_prompt
        text -> String.trim_leading("#{base_prompt}\n\n#{text}")
      end

    append_context(combined, context, budget)
  end

  defp estimate_tokens_for_messages(messages) do
    Enum.reduce(messages, 0, fn msg, acc ->
      content = Map.get(msg, :content, Map.get(msg, "content", ""))
      acc + estimate_tokens(to_string(content))
    end)
  end

  defp append_context(prompt, nil, _budget), do: {prompt, false}
  defp append_context(prompt, "", _budget), do: {prompt, false}

  defp append_context(prompt, context, budget) do
    prompt_tokens = estimate_tokens(prompt)
    context_tokens = estimate_tokens(context)
    separator_tokens = estimate_tokens(@context_separator)
    # Reserve ~25% of budget for task + history at minimum
    available = max(budget - prompt_tokens - separator_tokens - div(budget, 4), 0)

    if context_tokens <= available do
      {prompt <> @context_separator <> context, false}
    else
      # Truncate context to fit available budget
      available_chars = max(available * 4, 0)

      truncated_context =
        if available_chars > 20 do
          String.slice(context, 0, available_chars) <> "\n[context truncated]"
        else
          "[context truncated]"
        end

      {prompt <> @context_separator <> truncated_context, true}
    end
  end

  defp truncate_history([], _remaining), do: {[], [], 0, 0}

  defp truncate_history(history, remaining) do
    # Calculate tokens for each message
    indexed =
      history
      |> Enum.with_index()
      |> Enum.map(fn {msg, idx} ->
        content = Map.get(msg, :content, Map.get(msg, "content", ""))
        tokens = estimate_tokens(to_string(content))
        {msg, idx, tokens}
      end)

    full_total = Enum.reduce(indexed, 0, fn {_, _, t}, acc -> acc + t end)

    if full_total <= remaining do
      {history, [], full_total, full_total}
    else
      # Keep from newest, accumulating until budget is full
      {kept, dropped} = keep_from_newest(Enum.reverse(indexed), remaining)
      kept_tokens = Enum.reduce(kept, 0, fn {_, _, t}, acc -> acc + t end)
      dropped_indices = Enum.map(dropped, fn {_, idx, _} -> idx end)
      kept_msgs = Enum.map(kept, fn {msg, _, _} -> msg end)
      {kept_msgs, dropped_indices, kept_tokens, full_total}
    end
  end

  defp keep_from_newest(reversed_indexed, remaining) do
    {kept_rev, _budget_left} =
      Enum.reduce(reversed_indexed, {[], remaining}, fn {msg, idx, tokens}, {acc, left} ->
        if tokens <= left do
          {[{msg, idx, tokens} | acc], left - tokens}
        else
          {acc, left}
        end
      end)

    # kept_rev is in oldest-first order (reduce built it reversed from newest-first input)
    kept_set = MapSet.new(kept_rev, fn {_, idx, _} -> idx end)

    dropped =
      reversed_indexed
      |> Enum.reverse()
      |> Enum.reject(fn {_, idx, _} -> MapSet.member?(kept_set, idx) end)

    {kept_rev, dropped}
  end
end
