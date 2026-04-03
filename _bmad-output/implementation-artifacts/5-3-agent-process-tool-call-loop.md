# Story 5.3: AgentProcess & Tool Call Loop

Status: done

## Story

As a developer building the harness,
I want a single generic GenServer that loads any role from markdown and runs an LLM-driven tool call loop,
So that all agents use one well-tested executor regardless of role.

## Acceptance Criteria

### AC1: AgentSupervisor (DynamicSupervisor)

**Given** the application is started
**When** the supervision tree initializes
**Then** `Familiar.AgentSupervisor` is a `DynamicSupervisor` in the tree (replaces `LibrarianSupervisor` if present)
**And** it starts with `strategy: :one_for_one`
**And** agent processes are started under it via `DynamicSupervisor.start_child/2`

### AC2: AgentProcess GenServer — Init & Role Loading

**Given** a valid role name (e.g., `"coder"`)
**When** `AgentProcess.start_link(role: "coder", task: "implement auth", parent: pid)` is called
**Then** it starts a GenServer under `Familiar.AgentSupervisor`
**And** `init/1` loads the role via `Familiar.Roles.load_role/1`
**And** it resolves the role's skills via `Familiar.Roles.load_skill/1` for each skill in the role
**And** it creates a conversation via `Familiar.Conversations.create/2`
**And** it broadcasts `Hooks.event(:on_agent_start, %{agent_id: id, role: name, task: task})`
**And** it enters the tool-call loop via `{:ok, state, {:continue, :execute}}`

**Given** an invalid role name
**When** `AgentProcess.start_link(role: "nonexistent", task: "...", parent: pid)` is called
**Then** it returns `{:error, {:role_not_found, ...}}`

### AC3: Tool Call Loop (Core Execution)

**Given** an AgentProcess has initialized
**When** `handle_continue(:execute, state)` runs
**Then** it assembles messages: system prompt (from role) + task description + conversation history
**And** it calls `Providers.chat/2` with the assembled messages and `model: role.model`
**And** if the response contains no tool_calls → execution is complete
**And** if the response contains tool_calls → dispatch each via `ToolRegistry.dispatch/3`
**And** tool results are appended to conversation history as tool-role messages
**And** the loop repeats (another LLM call with updated history)
**And** each iteration broadcasts activity events for observability

### AC4: Tool Call Dispatch Integration

**Given** the LLM response contains tool_calls
**When** each tool call is dispatched
**Then** `ToolRegistry.dispatch(tool_name, args, context)` is called
**And** context includes `%{agent_id: id, role: role_name, conversation_id: conv_id}`
**And** `{:ok, result}` is formatted as a tool-role message with the result content
**And** `{:error, reason}` is formatted as a tool-role message with the error description
**And** `{:error, {:vetoed, reason}}` is formatted as a tool-role message explaining the veto

### AC5: Safety Limits

**Given** an AgentProcess is executing
**When** the tool call count exceeds the configurable max (default: 100)
**Then** execution stops with `{:error, {:max_tool_calls_exceeded, count}}`
**And** the agent broadcasts `Hooks.event(:on_agent_error, ...)` with the limit reason
**And** the parent (if any) is notified via `send(parent, {:agent_done, id, {:error, reason}})`

**Given** an AgentProcess is executing
**When** the per-task timeout (default: 5 minutes) is exceeded
**Then** execution stops with `{:error, {:timeout, elapsed_ms}}`
**And** the agent reports the timeout and shuts down gracefully

### AC6: Completion & Status Reporting

**Given** an AgentProcess completes (LLM returns no tool_calls)
**When** execution finishes
**Then** it broadcasts `Hooks.event(:on_agent_complete, %{agent_id: id, role: name, result: final_content})`
**And** it updates the conversation status to `"completed"`
**And** it notifies the parent via `send(parent, {:agent_done, id, {:ok, result}})`
**And** the GenServer terminates normally

**Given** an AgentProcess encounters an error
**When** execution fails (LLM error, crash, limit exceeded)
**Then** it broadcasts `Hooks.event(:on_agent_error, %{agent_id: id, role: name, error: reason})`
**And** it updates the conversation status to `"abandoned"`
**And** it notifies the parent via `send(parent, {:agent_done, id, {:error, reason}})`

### AC7: Public Query API

**Given** agents are running
**When** `AgentProcess.status(pid)` is called
**Then** it returns `{:ok, %{agent_id: id, role: name, status: atom, tool_calls: count, elapsed_ms: int}}`

**When** `AgentProcess.list_agents()` is called
**Then** it returns a list of `{pid, agent_id}` tuples for all children of `AgentSupervisor`

### AC8: Test Coverage

**Given** AgentProcess is implemented
**When** `mix test` runs
**Then** init with valid role loads role + skills and enters loop
**And** init with invalid role returns error
**And** tool call loop with mocked LLM (no tool calls) completes immediately
**And** tool call loop with mocked LLM (tool calls then done) dispatches tools and completes
**And** tool call dispatch uses ToolRegistry and passes correct context
**And** max tool call limit stops execution
**And** parent receives `{:agent_done, ...}` messages
**And** activity events broadcast for agent lifecycle
**And** conversation is created and messages are persisted
**And** near-100% coverage on `Familiar.Execution.AgentProcess`

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.AgentSupervisor` DynamicSupervisor (AC: 1)
  - [x] Create `lib/familiar/execution/agent_supervisor.ex`
  - [x] `use DynamicSupervisor`, `strategy: :one_for_one`
  - [x] `start_agent(opts)` convenience function wrapping `DynamicSupervisor.start_child/2`
  - [x] Add to supervision tree in `application.ex` (after ToolRegistry, before extensions)
  - [x] Remove `LibrarianSupervisor` from supervision tree if still present (not present — already removed)

- [x] Task 2: Create `Familiar.Execution.AgentProcess` GenServer (AC: 2)
  - [x] Create `lib/familiar/execution/agent_process.ex`
  - [x] `start_link(opts)` — accepts `role:`, `task:`, `parent:` (optional pid)
  - [x] Generate unique agent_id: `"agent_#{System.unique_integer([:positive, :monotonic])}"`
  - [x] `init/1`: load role via `Roles.load_role(role_name)`, load skills, create conversation, broadcast `on_agent_start`
  - [x] State struct: `%{agent_id, role, skills, task, parent, conversation_id, tool_call_count, status, started_at, max_tool_calls, task_timeout_ms, llm_task, timeout_ref, messages}`
  - [x] Return `{:ok, state, {:continue, :execute}}` on success
  - [x] Return `{:stop, {:role_not_found, reason}}` on role load failure

- [x] Task 3: Implement tool call loop (AC: 3, 4, 5)
  - [x] `handle_continue(:execute, state)` — kicks off async LLM call via Task.Supervisor
  - [x] Message assembly: `[%{role: "system", content: system_prompt}, %{role: "user", content: task_description}]` + conversation history
  - [x] System prompt: role.system_prompt + skill instructions concatenated
  - [x] Call `Providers.chat(messages, model: role.model)` via `Task.Supervisor.async_nolink` (non-blocking)
  - [x] Parse response: extract `content` and `tool_calls`
  - [x] If no tool_calls → save assistant message, complete
  - [x] If tool_calls → dispatch each, collect results, save messages, loop
  - [x] Tool dispatch: `ToolRegistry.dispatch(atom_name, args, context)` with safe atom conversion
  - [x] Context: `%{agent_id: state.agent_id, role: state.role.name, conversation_id: state.conversation_id}`
  - [x] Format tool results as messages: `%{role: "tool", content: Jason.encode!(result)}`
  - [x] Increment `tool_call_count` per dispatch
  - [x] Check max_tool_calls limit after each batch
  - [x] Timeout via `Process.send_after(self(), :task_timeout, remaining_ms)` per LLM call
  - [x] `handle_info(:task_timeout, state)` → kill LLM task, stop with timeout error
  - [x] Broadcast `Activity.broadcast/2` events during loop for observability

- [x] Task 4: Completion and error handling (AC: 6)
  - [x] On completion: broadcast `on_agent_complete`, update conversation to "completed", notify parent, return `{:stop, :normal, state}`
  - [x] On error: broadcast `on_agent_error`, update conversation to "abandoned", notify parent, return `{:stop, :normal, state}`
  - [x] `terminate/2`: final cleanup

- [x] Task 5: Public query API (AC: 7)
  - [x] `AgentProcess.status(pid)` → `GenServer.call(pid, :status)` — responsive during LLM calls
  - [x] `AgentProcess.list_agents()` → `DynamicSupervisor.which_children(AgentSupervisor)`
  - [x] Return formatted status maps

- [x] Task 6: Update Boundary and exports (AC: 1, 2)
  - [x] Add `Familiar.Execution.AgentProcess` to `Familiar.Execution` boundary exports
  - [x] Add `Familiar.Execution.AgentSupervisor` to boundary exports
  - [x] Add `Familiar.Roles` and `Familiar.Conversations` to `Familiar.Execution` deps

- [x] Task 7: Tests (AC: 8)
  - [x] Create `test/familiar/execution/agent_process_test.exs`
  - [x] Use `Familiar.DataCase` (needs DB for conversations) + Mox for LLM with global mode
  - [x] Test: init with valid role succeeds, loads role, creates conversation
  - [x] Test: init with invalid role returns error
  - [x] Test: LLM returns no tool_calls → agent completes immediately, parent notified
  - [x] Test: LLM returns tool_calls then no tool_calls → tools dispatched, agent completes
  - [x] Test: tool dispatch passes correct context (agent_id, role, conversation_id)
  - [x] Test: vetoed tool call formatted as error message to LLM
  - [x] Test: max tool call limit triggers error and shutdown
  - [x] Test: parent receives {:agent_done, id, result} messages
  - [x] Test: on_agent_start and on_agent_complete events broadcast
  - [x] Test: conversation created with messages persisted
  - [x] Test: status/1 returns current agent state (responsive during LLM call)
  - [x] Test: list_agents/0 returns running agents

- [x] Task 8: Credo, formatting, full regression (AC: 8)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (738 tests + 4 properties)

### Review Findings

- [x] [Review][Patch] System/user messages not persisted to conversation DB — fixed: persist system prompt and user task via `add_message` in init after conversation creation
- [x] [Review][Patch] Atom exhaustion via `String.to_atom` on LLM argument keys — fixed: use `String.to_existing_atom/1` with rescue fallback to keep unknown keys as strings
- [x] [Review][Patch] Stale timeout can kill subsequent LLM task — fixed: use tagged timeout messages `{:task_timeout, timer_id}` with unique `make_ref()` per iteration
- [x] [Review][Patch] `list_agents/0` bare rescue swallows all exceptions — fixed: log warning with exception message before returning `[]`
- [x] [Review][Patch] Missing `@impl true` on `:agent_id` handler — fixed: added annotation
- [x] [Review][Defer] Missing `tool_call_id` in tool result messages — OpenAI-compatible APIs require `tool_call_id` matching each tool call. Not needed for Ollama MVP; will matter when Anthropic/OpenAI adapters are added. Deferred to prompt assembly (Story 5.4) or provider adapter work.
- [x] [Review][Defer] Unbounded message history growth — up to 100 tool calls accumulate without truncation or token budget. Deferred to Story 5.4 (Prompt Assembly) which owns token budget management.
- [x] [Review][Defer] Synchronous tool dispatch blocks GenServer during tool execution — `ToolRegistry.dispatch/3` is a GenServer.call that blocks. Same as deferred item from Story 5.2. MVP is single-agent sequential.
- [x] [Review][Defer] `add_message` return value ignored — DB write failures silently lost. Low risk for SQLite MVP; should add error logging in a later hardening pass.
- [x] [Review][Defer] O(n^2) list appending in message accumulation — `state.messages ++ [msg]` is O(n). Acceptable for max 100 tool calls; optimize if limits increase.

## Dev Notes

### Architecture Constraints

- **One GenServer, many roles**: `AgentProcess` is the single executor for ALL agent types. Role files provide differentiation — no per-role Elixir modules.
- **Hexagonal architecture**: Use behaviour ports for LLM calls (`Familiar.Providers.LLM` via `Familiar.Providers.chat/2`). Mox mock in tests.
- **Error tuple convention**: `{:ok, result}` or `{:error, {atom_type, term}}`.
- **Conversations are DB-backed**: Use `Familiar.Conversations.create/2` and `add_message/4` to persist the full message history. Messages have `role` (user/assistant/system/tool) and `content` fields. `tool_calls` field is JSON string.
- **Tool functions return** `{:ok, result}` or `{:error, reason}`. Results must be serialized to string for the LLM message.

### Existing Infrastructure to Build On

| What | Where | How It's Used |
|------|-------|--------------|
| `Familiar.Providers` | `lib/familiar/providers/providers.ex` | `chat(messages, opts)` calls configured LLM impl. Messages: `[%{role: "system", content: "..."}]`. Returns `{:ok, %{content: str, tool_calls: [map], usage: map}}` |
| `Familiar.Providers.LLM` | `lib/familiar/providers/llm.ex` | Behaviour with `chat/2` and `stream_chat/2`. Test mock: `Familiar.Providers.LLMMock` |
| `Familiar.Roles` | `lib/familiar/roles/roles.ex` | `load_role(name, opts)` → `{:ok, %Role{name, description, system_prompt, model, lifecycle, skills}}`. `load_skill(name, opts)` → `{:ok, %Skill{name, instructions, tools, constraints}}` |
| `Familiar.Conversations` | `lib/familiar/conversations/conversations.ex` | `create(desc, opts)` → `{:ok, %Conversation{}}`. `add_message(conv_id, role, content, tool_calls: "[]")`. `messages(conv_id)` → `{:ok, [%Message{}]}`. `update_status(conv_id, status)` |
| `Familiar.Execution.ToolRegistry` | `lib/familiar/execution/tool_registry.ex` | `dispatch(name, args, context)` → `{:ok, result}` or `{:error, reason}`. Context map passed through to tool function and hooks |
| `Familiar.Hooks` | `lib/familiar/execution/hooks.ex` | `event(hook, payload)` for lifecycle events. Already registered hooks: `on_agent_start`, `on_agent_complete`, `on_agent_error` |
| `Familiar.Activity` | `lib/familiar/activity.ex` | `broadcast(scope_id, %Event{type, detail, result, timestamp})` for CLI streaming. `topic(scope_id)` for PubSub subscription |
| `Familiar.Providers.LLMMock` | `test/support/mocks.ex` | Mox mock for `Familiar.Providers.LLM` behaviour. Use `Mox.stub/3` or `Mox.expect/3` to script LLM responses |
| `Familiar.DataCase` | `test/support/data_case.ex` | Test case template with Ecto sandbox for DB access |

### Key Design Decisions

1. **Blocking `chat/2`, not streaming** — MVP uses `Providers.chat/2` (synchronous). Streaming adds complexity (accumulating deltas, handling partial tool calls). The tool-call loop needs the complete response to dispatch tools. Streaming can be layered on later by switching to `stream_chat/2` and accumulating events.

2. **GenServer with `handle_continue`** — The loop uses `handle_continue(:execute, state)` for the initial LLM call. Subsequent iterations use `handle_continue(:loop, state)` after tool results are collected. This keeps the GenServer responsive to `status/1` calls between iterations.

3. **Tool calls are sequential within an iteration** — When the LLM returns multiple tool_calls in one response, dispatch them sequentially (not in parallel). This is simpler and matches the convention that tool order may matter. Parallel tool dispatch is a later optimization.

4. **Parent notification via plain messages** — `send(parent, {:agent_done, agent_id, result})`. No GenServer.call — the parent may be another AgentProcess, a CLI process, or a test. Plain messages are the most flexible.

5. **Conversation persistence** — Every message (system, user, assistant, tool) is persisted via `Conversations.add_message/4`. This gives full replay capability and audit trail. The conversation_id is part of the agent's context passed to tool dispatch.

6. **Agent ID format** — Use `"agent_#{System.unique_integer([:positive, :monotonic])}"` for unique, sortable IDs. Not UUIDs — these are ephemeral process identifiers, not database primary keys.

7. **Tool name atom conversion** — LLM returns tool names as strings. Convert via `String.to_existing_atom/1` to prevent atom table pollution. If the atom doesn't exist, the tool isn't registered — return error to LLM.

8. **Timeout via `Process.send_after`** — Set a single timeout timer in `init/1`. If the agent completes before timeout, the timer message is ignored (agent process is dead). No need to cancel.

### LLM Response Format (from OllamaAdapter)

```elixir
# Providers.chat/2 returns:
{:ok, %{
  content: "I'll read the file now.",
  tool_calls: [
    %{"function" => %{"name" => "read_file", "arguments" => %{"path" => "lib/foo.ex"}}}
  ],
  usage: %{prompt_tokens: 150, completion_tokens: 42}
}}

# When no tool calls:
{:ok, %{content: "Here's the implementation...", tool_calls: [], usage: %{...}}}
```

Tool call format may vary by provider. Extract `name` and `arguments` from each tool call entry. Handle both string and atom keys defensively.

### Message Format for LLM

```elixir
# System + user + assistant + tool messages:
[
  %{role: "system", content: role_system_prompt <> "\n\n" <> skill_instructions},
  %{role: "user", content: "Task: implement auth handler"},
  %{role: "assistant", content: "I'll read the file.", tool_calls: [...]},
  %{role: "tool", content: ~s({"ok": {"content": "file contents here..."}})}
]
```

### Configuration

```elixir
# config/config.exs (or runtime.exs)
config :familiar, Familiar.Execution.AgentProcess,
  max_tool_calls: 100,
  task_timeout_ms: 300_000  # 5 minutes
```

### Previous Story Intelligence (5.2)

- **Test baseline**: 716 tests + 4 properties, 0 failures. Credo strict: 0 issues.
- **ToolRegistry.dispatch/3 runs inside GenServer** — deferred concern from 5.2 review. For this story, AgentProcess calls `ToolRegistry.dispatch/3` which blocks the ToolRegistry GenServer. This is fine for MVP single-agent sequential execution. If needed, dispatch could be moved to a Task or the agent's own process in a later story.
- **Tool function contract**: `(args :: map(), context :: map()) -> {:ok, result} | {:error, reason}`. Context carries agent_id, role, conversation_id.
- **after_tool_call broadcasts on ALL outcomes** — including errors. AgentProcess doesn't need to broadcast separately for tool results.
- **Hooks.event/2 is fire-and-forget** — safe to call from AgentProcess without error handling.

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── agent_process.ex          # NEW — Generic agent GenServer
├── agent_supervisor.ex       # NEW — DynamicSupervisor for agents

test/familiar/execution/
├── agent_process_test.exs    # NEW — tool call loop, lifecycle, limits
```

Modified files:
```
lib/familiar/application.ex          # Add AgentSupervisor to supervision tree
lib/familiar/execution/execution.ex  # Update Boundary exports + deps
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md — Decision A1: AgentProcess topology, supervision, spawning]
- [Source: _bmad-output/planning-artifacts/architecture.md — Lines 75-80: Agent runner tool call loop]
- [Source: _bmad-output/planning-artifacts/architecture.md — Decision A5: Harness core components list]
- [Source: _bmad-output/planning-artifacts/epics.md — Story 5.3 scope description]
- [Source: familiar/lib/familiar/providers/llm.ex — LLM behaviour, message types, response format]
- [Source: familiar/lib/familiar/providers/providers.ex — Provider delegation API]
- [Source: familiar/lib/familiar/roles/roles.ex — Role/skill loading API]
- [Source: familiar/lib/familiar/conversations/conversations.ex — Conversation CRUD]
- [Source: familiar/lib/familiar/execution/tool_registry.ex — dispatch/3, register/4 APIs]
- [Source: familiar/lib/familiar/execution/hooks.ex — event/2 for lifecycle broadcasts]
- [Source: familiar/lib/familiar/activity.ex — PubSub event broadcasting]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- `Familiar.Execution.AgentSupervisor` — DynamicSupervisor for all agent processes, with `start_agent/1` convenience function
- `Familiar.Execution.AgentProcess` — single generic GenServer for ALL agent roles, differentiated entirely by loaded role files
- Non-blocking LLM call via `Task.Supervisor.async_nolink` — GenServer remains responsive to `status/1` during LLM execution
- Tool call loop: assemble messages → async LLM call → parse tool_calls → dispatch via ToolRegistry → append results → repeat
- Tool call parsing handles multiple provider formats: `%{"function" => %{"name" => ...}}` and `%{"name" => ...}`, string and atom keys
- Safe atom conversion via `String.to_existing_atom/1` prevents atom table pollution from LLM-generated tool names
- Tool result formatting: `{:ok, result}` → JSON, `{:error, {:vetoed, reason}}` → veto message, `{:error, reason}` → error string
- Safety limits: configurable max_tool_calls (default 100) and task_timeout_ms (default 5 min) with per-LLM-call timeout enforcement
- Conversation persistence: every message (assistant + tool) saved via `Conversations.add_message/4`
- Lifecycle event broadcasting: `on_agent_start`, `on_agent_complete`, `on_agent_error` via `Hooks.event/2`
- Activity broadcasting for CLI streaming via `Activity.broadcast/2`
- Parent notification via plain `send(parent, {:agent_done, agent_id, result})` messages
- Boundary updated: `Familiar.Execution` exports AgentProcess + AgentSupervisor, deps include Roles + Conversations
- Test count: 716 → 738 (+22), 0 failures, Credo strict: 0 issues

### File List

- familiar/lib/familiar/execution/agent_process.ex (new)
- familiar/lib/familiar/execution/agent_supervisor.ex (new)
- familiar/lib/familiar/execution/execution.ex (modified — Boundary exports + deps)
- familiar/lib/familiar/application.ex (modified — AgentSupervisor in supervision tree)
- familiar/test/familiar/execution/agent_process_test.exs (new)

### Change Log

- 2026-04-03: Implemented Story 5.3 — AgentProcess & Tool Call Loop
