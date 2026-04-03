# Story 5.4: Prompt Assembly

Status: done

## Story

As a developer building the harness,
I want a pure function module that assembles role prompts, skill instructions, context, and conversation history into LLM messages,
So that prompt construction is testable, provider-agnostic, manages token budgets, and is decoupled from AgentProcess.

## Acceptance Criteria

### AC1: Module Extraction from AgentProcess

**Given** the current inline `build_system_prompt/2` and `assemble_messages/1` in `AgentProcess`
**When** the `Familiar.Execution.PromptAssembly` module is created
**Then** `AgentProcess` delegates to `PromptAssembly.assemble/2` instead of its private functions
**And** the existing AgentProcess tests continue to pass unchanged (no behavioral regression)
**And** `PromptAssembly` is a pure function module with no GenServer, no side effects, no process state

### AC2: Message Assembly — Core Contract

**Given** a role struct, a list of skill structs, a task string, and conversation history
**When** `PromptAssembly.assemble(state_or_params, opts \\ [])` is called
**Then** it returns `{messages, metadata}` where:
- `messages` is a list of `%{role: String.t(), content: String.t()}` maps ready for `Providers.chat/2`
- `metadata` is `%{truncated: boolean, dropped_entries: list, token_budget: map}`
**And** messages are ordered: `[system, user_task | conversation_history]`
**And** the system message combines role.system_prompt + skill instructions (joined by `"\n\n"`)
**And** nil system_prompt or nil skill instructions are handled gracefully (empty string fallback)

### AC3: Token Budget Management

**Given** a configurable token budget (default from role.model config or fallback)
**When** the total estimated token count of all messages exceeds the budget
**Then** conversation history is truncated from the oldest messages (preserving system + task + most recent messages)
**And** `metadata.truncated` is `true`
**And** `metadata.dropped_entries` lists the dropped message indices
**And** `metadata.token_budget` reports `%{limit: int, estimated: int, after_truncation: int}`
**And** the system message and user task message are never truncated (they are always included)

**Given** total messages fit within the token budget
**When** assembly completes
**Then** `metadata.truncated` is `false` and `metadata.dropped_entries` is `[]`

### AC4: Token Estimation

**Given** messages to estimate
**When** `PromptAssembly.estimate_tokens/1` is called with a string or list of messages
**Then** it returns an integer estimate using a character-based heuristic (chars / 4, rounded up)
**And** this is a pure function with no external dependencies (no provider calls)
**And** a future story can swap in a provider-specific tokenizer without changing the interface

### AC5: Context Block Injection

**Given** an optional context block (string of knowledge store entries or other injected context)
**When** passed via `opts[:context]`
**Then** it is appended to the system message after role prompt and skill instructions
**And** it is separated by `"\n\n---\n\n"` delimiter
**And** if the context block alone exceeds the remaining budget after system+task, it is truncated with a `[context truncated]` marker
**And** context truncation is reflected in metadata

### AC6: Tool Definitions Assembly

**Given** a role with skills that reference tools
**When** assembling messages
**Then** `PromptAssembly.tool_definitions/1` extracts tool schemas from the skill structs' tool lists
**And** these are returned as a separate field alongside messages: `{messages, tools, metadata}`
**And** `AgentProcess` can pass tool definitions to `Providers.chat/2` when provider supports it

### AC7: AgentProcess Integration

**Given** `PromptAssembly` is extracted and working
**When** `AgentProcess` calls `PromptAssembly.assemble/2` in its loop
**Then** the returned messages are passed directly to `Providers.chat/2`
**And** truncation metadata is logged via `Logger.info` when truncation occurs
**And** the `build_system_prompt/2` and `assemble_messages/1` private functions are removed from AgentProcess

### AC8: Test Coverage

**Given** `PromptAssembly` is implemented
**When** `mix test` runs
**Then** pure function tests cover: basic assembly, nil handling, skill concatenation, message ordering
**And** token estimation tests verify heuristic accuracy on known strings
**And** truncation tests verify: budget exceeded triggers truncation, system+task never dropped, metadata accurate
**And** context injection tests verify: context appended, context truncated when oversized
**And** property-based test: output never exceeds token budget for any valid input combination
**And** AgentProcess integration tests still pass (no regression)
**And** near-100% coverage on `Familiar.Execution.PromptAssembly`

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Execution.PromptAssembly` module (AC: 1, 2)
  - [x] Create `lib/familiar/execution/prompt_assembly.ex`
  - [x] `assemble/2` — takes a map/struct with `:role`, `:skills`, `:task`, `:messages` keys + opts keyword list
  - [x] Returns `{messages, metadata}` tuple
  - [x] `build_system_prompt/2` extracted from AgentProcess — combines `role.system_prompt` + skill instructions
  - [x] Handle nil system_prompt and nil instructions with `|| ""` fallback
  - [x] Message ordering: `[%{role: "system", content: system_prompt}, %{role: "user", content: task} | history]`

- [x] Task 2: Token estimation (AC: 4)
  - [x] `estimate_tokens/1` for a single string — `ceil(String.length(string) / 4)`
  - [x] `estimate_tokens/1` for a list of message maps — sum of content estimates
  - [x] Pure function, no side effects, no provider calls

- [x] Task 3: Token budget and truncation (AC: 3)
  - [x] Accept `opts[:token_budget]` (integer) — default `128_000` (sensible default for modern models)
  - [x] Calculate total token estimate for assembled messages
  - [x] If over budget: drop conversation history from oldest first, keeping system + user task + most recent N messages that fit
  - [x] Build metadata: `%{truncated: bool, dropped_entries: [int], token_budget: %{limit: int, estimated: int, after_truncation: int}}`
  - [x] System message and user task message are NEVER truncated

- [x] Task 4: Context block injection (AC: 5)
  - [x] Accept `opts[:context]` (string or nil)
  - [x] Append to system message with `"\n\n---\n\n"` separator
  - [x] If context alone exceeds remaining budget, truncate with `"[context truncated]"` marker
  - [x] Include context size in token estimate calculations

- [x] Task 5: Tool definitions extraction (AC: 6)
  - [x] `tool_definitions/1` — accepts list of skill structs
  - [x] Extracts tool names from each skill's `.tools` field
  - [x] Returns flat deduplicated list of tool name strings — kept as strings since ToolRegistry lookup and Providers.chat/2 tool schemas are not yet wired (MVP)
  - [x] Decision: return `{messages, metadata}` from assemble/2 (not 3-tuple) — tool definitions is a separate function, not bundled into assembly return

- [x] Task 6: Refactor AgentProcess to use PromptAssembly (AC: 7)
  - [x] Replace `assemble_messages/1` call with `PromptAssembly.assemble/2`
  - [x] Remove `build_system_prompt/2` and `assemble_messages/1` private functions
  - [x] Add `alias Familiar.Execution.PromptAssembly`
  - [x] Log truncation metadata when `metadata.truncated == true`
  - [x] Ensure all existing AgentProcess tests pass without modification

- [x] Task 7: Update Boundary exports (AC: 1)
  - [x] Add `Familiar.Execution.PromptAssembly` to `Familiar.Execution` boundary exports

- [x] Task 8: Pure function tests (AC: 8)
  - [x] Create `test/familiar/execution/prompt_assembly_test.exs`
  - [x] Test: basic assembly with role + skills + task → correct message list
  - [x] Test: nil system_prompt → empty string in system message
  - [x] Test: nil skill instructions → only role prompt in system message
  - [x] Test: empty skills list → only role prompt
  - [x] Test: multiple skills concatenated with `"\n\n"`
  - [x] Test: message ordering (system first, user second, history follows)
  - [x] Test: token estimation on known strings (predictable length)
  - [x] Test: under budget → `truncated: false`, empty dropped_entries
  - [x] Test: over budget → history truncated from oldest, system+task preserved
  - [x] Test: context injection appended to system message
  - [x] Test: oversized context truncated with marker
  - [x] Test: tool_definitions extraction from skills
  - [x] Property test (StreamData): for any valid inputs, output token estimate <= budget

- [x] Task 9: Credo, formatting, full regression (AC: 8)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (769 tests + 5 properties)

### Review Findings

- [x] [Review][Decision] AC6 return signature — resolved: implement 3-tuple `{messages, tools, metadata}` for future-proofing; AgentProcess destructures `_tools` for now
- [x] [Review][Patch] `drop_from_oldest/3` greedy truncation — fixed: replaced with `keep_from_newest/2` that accumulates from newest, only keeping messages that fit within remaining budget
- [x] [Review][Patch] Leading `"\n\n"` in system prompt when nil — fixed: `String.trim_leading/1` on combined prompt
- [x] [Review][Patch] Context truncation not reflected in metadata — fixed: added `context_truncated: boolean` field to metadata; `append_context` returns `{content, truncated_flag}`
- [x] [Review][Patch] Property test does not assert budget invariant — fixed: asserts `history_tokens <= remaining_budget` as core invariant
- [x] [Review][Patch] Double token estimation of history — fixed: `truncate_history` returns 4-tuple including `full_history_tokens`; `assemble/2` uses it directly
- [x] [Review][Defer] Default token budget not derived from `role.model` config — AC3 says "default from role.model config or fallback" but implementation uses hardcoded 128k; no model-to-budget mapping exists yet — deferred to provider config story
- [x] [Review][Defer] `estimate_tokens_for_messages` doesn't count tool_calls payload tokens — assistant messages with tool_calls but nil content estimate as 0 tokens; deferred to provider adapter work when tool_call_id support is added

## Dev Notes

### Architecture Constraints

- **Pure function module** — no GenServer, no processes, no side effects. PromptAssembly is independently testable with inputs and assertions. [Source: architecture.md lines 65, 531]
- **100% coverage enforced** — architecture mandates 100% coverage on PromptAssembly because "prompt bugs silently degrade every task's output". [Source: architecture.md line 539]
- **Property-based testing required** — StreamData property: "output never exceeds token budget; truncation metadata is accurate". [Source: architecture.md line 551]
- **Infrastructure, not content** — PromptAssembly assembles prompts from role files. It does NOT define prompt content. All prompt text comes from `.familiar/roles/` and `.familiar/skills/` markdown files. [Source: architecture.md line 1587]
- **Hexagonal architecture** — no direct dependency on providers or DB. Takes data in, returns data out.

### Existing Code to Extract

The current implementation lives in `AgentProcess` (lines 333-355):

```elixir
defp assemble_messages(state) do
  system_prompt = build_system_prompt(state.role, state.skills)
  task_msg = %{role: "user", content: state.task}
  [%{role: "system", content: system_prompt}, task_msg | state.messages]
end

defp build_system_prompt(role, skills) do
  skill_text =
    skills
    |> Enum.map(fn skill -> skill.instructions end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")

  case skill_text do
    "" -> role.system_prompt || ""
    text -> "#{role.system_prompt || ""}\n\n#{text}"
  end
end
```

This is ~20 lines. The story adds token budget management, context injection, and truncation logic around this core.

### Token Estimation Strategy

Use character-based heuristic: `ceil(String.length(text) / 4)`. This is intentionally simple:
- No dependency on tiktoken or provider-specific tokenizers
- Accurate enough for budget management (within ~20% of actual)
- Can be swapped for a real tokenizer later without changing the public API
- The architecture doc says prompt assembly is a pure function — calling an external tokenizer would break that

### Deferred Items from Story 5-3 That This Story Addresses

1. **Unbounded message history growth** — This story adds token budget management with truncation. Oldest conversation messages dropped first when budget exceeded.
2. **Missing `tool_call_id` in tool result messages** — Evaluate during implementation. If provider-specific formatting is needed (tool_call_id for OpenAI), PromptAssembly can normalize messages per provider. For Ollama MVP, this may remain deferred.

### Deferred Items (NOT in scope)

- **Provider-specific prompt formatting** (Ollama vs Anthropic message formats) — Ollama adapter already normalizes in `normalize_messages/1`. Anthropic adapter doesn't exist yet. Defer until multi-provider story.
- **Ablation testing hooks** — Architecture mentions prompt assembly as the ablation injection point. Defer to thesis validation (post-MVP).
- **Real tokenizer integration** — Heuristic is sufficient for MVP. Exact token counting can be added when needed.

### Key Data Types

```elixir
# Input — role and skill structs from Familiar.Roles
%Familiar.Roles.Role{
  name: "coder",
  system_prompt: "You are a coding assistant...",
  model: "llama3.2",
  skills: ["implement", "test"],
  lifecycle: %{}
}

%Familiar.Roles.Skill{
  name: "implement",
  instructions: "When implementing code...",
  tools: ["read_file", "write_file"],
  constraints: []
}

# Output — messages for Providers.chat/2
{
  [%{role: "system", content: "..."}, %{role: "user", content: "..."}, ...],
  %{truncated: false, dropped_entries: [], token_budget: %{limit: 128_000, estimated: 450, after_truncation: 450}}
}
```

### LLM Response Usage Data

The provider already returns `usage: %{prompt_tokens: int, completion_tokens: int}` in responses. PromptAssembly doesn't use this (it's a pre-call assembly step), but AgentProcess could log actual vs estimated tokens for future calibration.

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── prompt_assembly.ex       # NEW — Pure function prompt assembly

test/familiar/execution/
├── prompt_assembly_test.exs # NEW — Pure function + property tests
```

Modified files:
```
lib/familiar/execution/agent_process.ex  # MODIFIED — delegate to PromptAssembly
lib/familiar/execution/execution.ex      # MODIFIED — add PromptAssembly to exports
```

### References

- [Source: architecture.md#Process Architecture — "Prompt Assembly Pipeline" (line 65)]
- [Source: architecture.md#Data Flow — "prompt assembly as thesis-critical transformation" (lines 184-192)]
- [Source: architecture.md#Testing Strategy — "100% coverage, property tests" (lines 539, 551)]
- [Source: architecture.md#Addendum Decision A3 — "PromptAssembly survives as infrastructure" (lines 1585-1587)]
- [Source: epics.md#Story 5.4 — scope definition (line 1288)]
- [Source: 5-3-agent-process-tool-call-loop.md — deferred items (lines 189, 188)]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Extracted `build_system_prompt/2` and `assemble_messages/1` from AgentProcess into pure function PromptAssembly module
- Token estimation via chars/4 heuristic — no external dependencies
- Token budget management with oldest-first history truncation; system+task messages never dropped
- Context block injection with `\n\n---\n\n` separator and truncation marker for oversized contexts
- `tool_definitions/1` returns flat deduplicated tool name list from skills — kept separate from assemble/2 return value
- AgentProcess refactored to delegate to PromptAssembly.assemble/2, logs truncation metadata
- 31 tests + 1 StreamData property covering all ACs; 0 regressions in existing 769-test suite
- Credo strict: 0 issues

### File List

- `familiar/lib/familiar/execution/prompt_assembly.ex` — NEW: pure function prompt assembly module
- `familiar/test/familiar/execution/prompt_assembly_test.exs` — NEW: 31 tests + 1 property
- `familiar/lib/familiar/execution/agent_process.ex` — MODIFIED: delegate to PromptAssembly, remove inline assembly functions
- `familiar/lib/familiar/execution/execution.ex` — MODIFIED: add PromptAssembly to boundary exports
