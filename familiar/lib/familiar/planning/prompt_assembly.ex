defmodule Familiar.Planning.PromptAssembly do
  @moduledoc """
  Pure function module for assembling planning conversation prompts.

  Transforms a context block and conversation history into a system prompt
  and message list suitable for `Providers.chat/2`. The initial user
  description is included in the history (persisted as the first message).

  This is a critical module with 100% test coverage required.
  """

  @planning_system_prompt """
  You are a planning assistant for a software project. Your job is to help the user \
  refine their feature description into a clear, actionable specification.

  ## Rules

  1. **Adaptive depth**: Gauge the clarity of the user's intent from their description.
     - If the description is vague or short (e.g., "make search better"), ask 3-5 clarifying questions.
     - If the description is detailed with specific file references or clear scope, ask 0-2 questions.
     - Each question should surface an edge case, ambiguity, or unresolved decision.

  2. **Never repeat questions**: Review the conversation history carefully. Never ask a question \
  that has already been answered or that can be inferred from prior answers.

  3. **Use context**: You have been provided with project context from the knowledge store. \
  Use it to inform your questions and avoid asking about things already known. \
  When referencing context, cite the source: "Based on [source_file]..."

  4. **Novel questions only**: Each question must add new information to the conversation. \
  Questions that rephrase or overlap with previous questions are a system failure.

  5. **Signal completion**: When you have enough information to write a specification, \
  respond with a message that starts with "[SPEC_READY]" followed by a brief summary \
  of what you'll specify. Do not generate the spec itself — that happens in the next phase.

  6. **Format**: Ask one question at a time. Keep questions concise and specific.
  """

  @type context_block :: String.t() | nil
  @type message :: %{role: String.t(), content: String.t()}
  @type conversation_history :: [message()]

  @doc """
  Assemble a prompt for the planning conversation.

  Takes a context block (from the Librarian, persisted on the session) and
  the full conversation history (from planning_messages, including the
  initial user description as the first message).

  Returns `{system_prompt, messages}` where:
  - `system_prompt` is the instruction string for the LLM
  - `messages` is a list of `%{role, content}` maps ready for `Providers.chat/2`
  """
  @spec assemble(context_block(), conversation_history()) :: {String.t(), [message()]}
  def assemble(context_block, conversation_history \\ [])

  def assemble(context_block, conversation_history) do
    system = build_system_prompt(context_block)
    messages = build_messages(system, conversation_history)
    {system, messages}
  end

  @doc """
  Extract the system prompt template (for testing/inspection).
  """
  @spec system_prompt_template() :: String.t()
  def system_prompt_template, do: @planning_system_prompt

  # -- Private --

  defp build_system_prompt(nil), do: @planning_system_prompt
  defp build_system_prompt(""), do: @planning_system_prompt

  defp build_system_prompt(context_block) do
    @planning_system_prompt <>
      "\n## Project Context\n\n" <>
      context_block
  end

  defp build_messages(system, []) do
    [%{role: "system", content: system}]
  end

  defp build_messages(system, history) do
    [%{role: "system", content: system} | normalize_history(history)]
  end

  defp normalize_history(history) do
    Enum.map(history, fn msg ->
      %{
        role: to_string(msg[:role] || msg["role"]),
        content: to_string(msg[:content] || msg["content"])
      }
    end)
  end
end
