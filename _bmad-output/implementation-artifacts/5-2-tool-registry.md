# Story 5.2: Tool Registry

Status: done

## Story

As a developer building the harness,
I want a central registry mapping tool names to Elixir implementations that dispatches through the hooks pipeline,
So that extensions can register tools and every tool call flows through safety checks.

## Acceptance Criteria

### AC1: ToolRegistry GenServer

**Given** the harness is started
**When** `Familiar.Execution.ToolRegistry` is running
**Then** it is a named GenServer started in the application supervision tree (after `Familiar.Hooks`)
**And** it holds a map of `tool_name (atom) => %{function: fun/2, description: String.t(), extension: String.t()}`
**And** it supports registration and lookup of tools

### AC2: Tool Registration

**Given** the ToolRegistry is running
**When** `ToolRegistry.register(name, function, description, extension_name)` is called
**Then** the tool is stored in the registry keyed by `name`
**And** duplicate registration of the same name logs a warning and overwrites the previous entry
**And** `ToolRegistry.list_tools()` returns all registered tools as `[%{name: atom(), description: String.t(), extension: String.t()}]`

### AC3: Tool Dispatch with Hooks Pipeline

**Given** a tool `:read_file` is registered
**When** `ToolRegistry.dispatch(:read_file, %{path: "foo.ex"}, context)` is called
**Then** the dispatch flow is:
  1. Call `Hooks.alter(:before_tool_call, %{tool: :read_file, args: %{path: "foo.ex"}}, context)`
  2. If alter returns `{:halt, reason}` → return `{:error, {:vetoed, reason}}`
  3. If alter returns `{:ok, possibly_modified_payload}` → extract (possibly modified) args
  4. Execute the tool function: `fun.(args, context)`
  5. Broadcast `Hooks.event(:after_tool_call, %{tool: :read_file, args: args, result: result})`
  6. Return `{:ok, result}` or `{:error, reason}` from the tool function

**Given** a tool is not registered
**When** `ToolRegistry.dispatch(:unknown_tool, args, context)` is called
**Then** it returns `{:error, {:unknown_tool, :unknown_tool}}`

### AC4: Core Built-In Tool Stubs

**Given** the ToolRegistry is initialized
**When** core tools are registered via `ToolRegistry.register_builtins/0`
**Then** these tools are available as stubs that return `{:error, {:not_implemented, %{tool: name}}}`:
  - `:read_file` — "Read the contents of a file at the given path"
  - `:write_file` — "Write content to a file at the given path"
  - `:delete_file` — "Delete a file at the given path"
  - `:list_files` — "List files matching a glob pattern"
  - `:run_command` — "Run a shell command from the configured allow-list"
  - `:spawn_agent` — "Spawn a child agent process with a given role and task"
  - `:monitor_agents` — "List running agent processes and their status"
  - `:broadcast_status` — "Broadcast a status message to PubSub subscribers"
  - `:signal_ready` — "Signal that the current workflow step is complete"

**And** stubs are registered with extension name `"harness"` to distinguish from extension-provided tools

### AC5: Tool Schema Export for LLM

**Given** tools are registered in the registry
**When** `ToolRegistry.tool_schemas()` is called
**Then** it returns a list of maps suitable for LLM tool-call schemas:
```elixir
[
  %{
    name: :read_file,
    description: "Read the contents of a file at the given path",
    extension: "harness"
  },
  ...
]
```
**And** the format matches what prompt assembly (Story 5.4) will consume

### AC6: Extension Tool Integration

**Given** the ExtensionLoader collects tools from extensions
**When** the application starts and extensions are loaded
**Then** `Application.start/2` calls `ToolRegistry.register/4` for each collected tool
**And** extension tools are registered with the extension's name

### AC7: Test Coverage

**Given** the ToolRegistry is implemented
**When** `mix test` runs
**Then** registration and lookup are tested
**And** dispatch through hooks pipeline is tested (alter pass-through, alter veto)
**And** dispatch of unregistered tools returns error
**And** duplicate registration overwrites with warning
**And** core builtin stubs return `{:error, {:not_implemented, _}}`
**And** `tool_schemas/0` returns correct format
**And** near-100% coverage on `Familiar.Execution.ToolRegistry`

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Execution.ToolRegistry` GenServer (AC: 1, 2)
  - [x]Create `lib/familiar/execution/tool_registry.ex`
  - [x]State: `%{tools: %{atom() => %{function: fun, description: String.t(), extension: String.t()}}}`
  - [x]`start_link/1` with named process (`__MODULE__`)
  - [x]`register(name, function, description, extension_name)` — stores tool; warns on duplicate via Logger
  - [x]`list_tools/0` — returns `[%{name: atom(), description: String.t(), extension: String.t()}]`
  - [x]`get_tool(name)` — returns `{:ok, tool_entry}` or `{:error, {:unknown_tool, name}}`

- [x] Task 2: Implement `dispatch/3` with hooks pipeline (AC: 3)
  - [x]`dispatch(name, args, context)` — the core dispatch function
  - [x]Step 1: `get_tool(name)` — return error if missing
  - [x]Step 2: `Hooks.alter(:before_tool_call, %{tool: name, args: args}, context)` — if `{:halt, reason}`, return `{:error, {:vetoed, reason}}`
  - [x]Step 3: Extract possibly modified args from alter result payload
  - [x]Step 4: Execute `tool.function.(args, context)` in try/rescue for crash safety
  - [x]Step 5: Broadcast `Hooks.event(:after_tool_call, %{tool: name, args: args, result: result})`
  - [x]Step 6: Return tool function result

- [x] Task 3: Register core built-in tool stubs (AC: 4)
  - [x]`register_builtins/0` — registers all 9 core tools as stubs
  - [x]Each stub: `fn _args, _ctx -> {:error, {:not_implemented, %{tool: name}}} end`
  - [x]Extension name for builtins: `"harness"`
  - [x]These stubs will be replaced with real implementations in later stories (5.3 for spawn_agent, 5.5 for file ops, etc.)

- [x] Task 4: Tool schema export (AC: 5)
  - [x]`tool_schemas/0` — returns list of `%{name, description, extension}` maps
  - [x]This is what prompt assembly (Story 5.4) will consume to build LLM function-calling schemas

- [x] Task 5: Wire into application startup (AC: 6)
  - [x]Add `Familiar.Execution.ToolRegistry` to supervision tree in `application.ex` (after Hooks, before extensions load)
  - [x]After `ExtensionLoader.load_extensions/1` returns, register each collected tool via `ToolRegistry.register/4`
  - [x]Call `ToolRegistry.register_builtins/0` before extension tools (so extensions can override)
  - [x]Update `Familiar.Execution` boundary exports to include `ToolRegistry`

- [x] Task 6: Tests (AC: 7)
  - [x]Create `test/familiar/execution/tool_registry_test.exs`
  - [x]Test: register + list_tools returns registered tool
  - [x]Test: get_tool returns tool entry or error
  - [x]Test: dispatch calls tool function and returns result
  - [x]Test: dispatch runs before_tool_call alter hook before execution
  - [x]Test: dispatch with alter veto returns `{:error, {:vetoed, reason}}`
  - [x]Test: dispatch with modified args from alter uses modified args
  - [x]Test: dispatch unknown tool returns `{:error, {:unknown_tool, name}}`
  - [x]Test: dispatch with crashing tool returns error, does not crash registry
  - [x]Test: duplicate register overwrites and logs warning
  - [x]Test: register_builtins registers all 9 tools as stubs returning not_implemented
  - [x]Test: tool_schemas returns correct format
  - [x]Test: after_tool_call event is broadcast after dispatch

- [x] Task 7: Credo, formatting, full regression (AC: 7)
  - [x]`mix format` passes
  - [x]`mix credo --strict` passes with 0 issues
  - [x]Full test suite passes with 0 failures

### Review Findings

- [x] [Review][Patch] Non-standard tool return values produce misleading `tool_crashed` error — fixed: added `other` catch-all clause returning `{:error, {:invalid_return, other}}`
- [x] [Review][Patch] `register_builtins/0` not tested through real function — fixed: added test calling real `ToolRegistry.register_builtins/0` against global process
- [x] [Review][Patch] `after_tool_call` not broadcast on tool error and not tested — fixed: `do_dispatch` now broadcasts on all outcomes; added 2 PubSub subscription tests
- [x] [Review][Patch] ExtensionLoader `@spec` still says 3-tuple after 4-tuple change — fixed: updated to `{atom(), function(), String.t(), String.t()}`
- [x] [Review][Defer] `dispatch/3` runs tool inside GenServer process, blocking all callers — deferred, MVP is single-agent sequential; Story 5.3 AgentProcess will own execution concurrency
- [x] [Review][Defer] Public API hardcoded to `__MODULE__` — tests use GenServer.call directly for isolation — deferred, same pattern as Hooks (intentional singleton; tests use named instances with direct GenServer calls)
- [x] [Review][Defer] Hooks GenServer down causes dispatch to crash ToolRegistry — deferred, OTP supervision restarts; same issue exists in Hooks (deferred in 5.1)
- [x] [Review][Defer] Hook registration missing `:type` key crashes loader — deferred, pre-existing in ExtensionLoader from Story 5.1
- [x] [Review][Defer] Circuit breaker key collision with same priority — deferred, pre-existing in Hooks from Story 5.1

## Dev Notes

### Architecture Constraints

- **Hexagonal architecture**: ToolRegistry follows the same GenServer pattern as `Familiar.Hooks` — named process, public API with spec, state in GenServer.
- **Error tuple convention**: Return `{:ok, result}` or `{:error, {atom_type, term}}`. Specific error atoms: `:unknown_tool`, `:vetoed`, `:not_implemented`, `:tool_crashed`.
- **`use Boundary`**: Update `Familiar.Execution` exports to include `ToolRegistry` alongside `Extension` and `Hooks`.
- **No Ecto/DB**: Purely in-memory GenServer state. No schemas, no migrations.
- **Hooks integration**: `dispatch/3` is the single chokepoint where `before_tool_call` and `after_tool_call` hooks fire. This is where safety enforcement (Story 5.6) will intercept tool calls.

### Existing Infrastructure to Build On

| What | Where | How It's Used |
|------|-------|--------------|
| `Familiar.Hooks` | `lib/familiar/execution/hooks.ex` | `alter/3` for before_tool_call pipeline, `event/2` for after_tool_call broadcast. Already in supervision tree. |
| `Familiar.Extension` | `lib/familiar/execution/extension.ex` | `@type tool_registration :: {atom(), function(), String.t()}` — this is what extensions return from `tools/0`. |
| `Familiar.Execution.ExtensionLoader` | `lib/familiar/execution/extension_loader.ex` | Returns `{:ok, %{tools: [tool_registrations], ...}}`. Tools collected but not yet registered anywhere — this story consumes them. |
| `Familiar.Application` | `lib/familiar/application.ex` | Extension loading in `load_extensions/0` already calls `ExtensionLoader.load_extensions/1` and gets tools back. Wire `ToolRegistry.register/4` calls here. |
| `Familiar.Activity` | `lib/familiar/activity.ex` | PubSub broadcasting for events. Hooks.event already uses this for after_tool_call. |
| `Familiar.Roles.Validator` | `lib/familiar/roles/validator.ex` | `@mvp_tools` list: `read_file, write_file, list_files, search_files, run_shell, search_context, store_context`. These validate skill files. The ToolRegistry core tools should be a superset. |

### Key Design Decisions

1. **GenServer, not ETS** — Same reasoning as Hooks: tool registrations change infrequently (on startup + extension load). Simple map in GenServer state. Dispatch is called frequently but lookup is O(1) map access.

2. **dispatch/3 is the chokepoint** — Every tool call goes through `dispatch/3`. This is where:
   - Safety extension's `before_tool_call` alter hook vetoes dangerous operations
   - Args can be modified by alter hooks (e.g., path canonicalization)
   - `after_tool_call` event fires for logging/knowledge capture
   - This pattern means NO tool can bypass safety — there is no "direct function call" path.

3. **Core tools are stubs** — The 9 core tools (read_file, write_file, etc.) are registered as stubs returning `{:error, {:not_implemented, %{}}}`. Real implementations come in later stories:
   - File ops (read_file, write_file, delete_file, list_files) → Story 5.9 (file transactions)
   - run_command → Story 5.3 or 5.6 (safety-gated shell)
   - spawn_agent, monitor_agents → Story 5.3 (AgentProcess)
   - broadcast_status, signal_ready → Story 5.8 (workflow runner)
   Later stories will call `ToolRegistry.register/4` to replace stubs with real implementations.

4. **Extension name tracking** — Each tool registration includes the extension name (`"harness"` for builtins, extension `name()` for extension tools). This enables `tool_schemas/0` to show provenance and debugging of which extension provided which tool.

5. **Alter payload contract** — The `before_tool_call` alter payload is `%{tool: atom(), args: map()}`. After alter processing, the possibly-modified args are extracted from the returned payload. This allows safety extensions to normalize paths or sanitize args before execution.

6. **Tool function contract** — Tool implementations are `(args :: map(), context :: map()) -> {:ok, result} | {:error, reason}`. The context map carries agent identity, scope, and any per-dispatch metadata.

7. **Tool crash isolation** — If a tool function raises, `dispatch/3` catches it and returns `{:error, {:tool_crashed, message}}`. The registry itself never crashes from a tool failure.

### Naming Note: run_command vs run_shell

The architecture uses `run_command`. The validator's `@mvp_tools` has `run_shell`. The skill files use `run_shell`. The ToolRegistry should register `run_command` (architecture canonical name). Story 5.6 (Safety Extension) or a later story should reconcile the naming. For now, register both `run_command` and add `search_files` as a builtin stub too (it's in `@mvp_tools`). Total: 11 builtin stubs.

**Updated builtin list** (reconciling architecture + @mvp_tools):
- From architecture: `read_file`, `write_file`, `delete_file`, `list_files`, `run_command`, `spawn_agent`, `monitor_agents`, `broadcast_status`, `signal_ready`
- From @mvp_tools also: `search_files`, `run_shell` (alias for run_command)
- From Knowledge Store extension (NOT builtins, registered by extension): `search_context`, `store_context`

Register the 9 architecture tools as builtins. `search_files` is a reasonable builtin too (10 total). `run_shell` vs `run_command` — register as `run_command` per architecture. `search_context`/`store_context` will come from the KnowledgeStore extension (Story 5.7). `search_files` is a file-system tool that belongs with builtins.

**Final builtin count: 10 stubs** — read_file, write_file, delete_file, list_files, search_files, run_command, spawn_agent, monitor_agents, broadcast_status, signal_ready.

### Testing Strategy

- **Per-test named GenServer** — same pattern as hooks_test.exs: `start_supervised!({ToolRegistry, name: unique_name})`, call functions with explicit server name or use helper functions that call GenServer directly.
- **Hooks integration** — For dispatch tests that need hooks, also start a named Hooks GenServer per test and register alter/event hooks on it. OR: test dispatch logic with the global Hooks (since it's started in test setup). Simplest: mock the hooks interaction by registering test hooks.
- **No Mox needed** — test with concrete anonymous functions and test module stubs.
- `use ExUnit.Case, async: true` — no DB needed.
- `capture_log` for duplicate registration warnings and tool crash warnings.

### Previous Story Intelligence (5.1)

- **Test baseline**: 696 tests + 4 properties, 0 failures. Credo strict: 0 issues.
- **Hooks.alter/3 uses `__MODULE__` as default GenServer name** — for ToolRegistry dispatch integration, call `Hooks.alter/3` which routes to the global Hooks GenServer. This is fine for production; tests that need hook isolation start their own named Hooks instance.
- **ExtensionLoader returns tools but they're unused** — `Application.load_extensions/0` pattern-matches `tools` from the result but does nothing with them. This story wires them into ToolRegistry.
- **Event dispatch uses direct PubSub** — `Hooks.event/2` broadcasts `{:hook_event, hook, payload}` tuples via `Phoenix.PubSub.broadcast/3`. After_tool_call events will use this same pattern.

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── tool_registry.ex         # NEW — Familiar.Execution.ToolRegistry GenServer

test/familiar/execution/
├── tool_registry_test.exs   # NEW — registration, dispatch, hooks integration
```

Modified files:
```
lib/familiar/application.ex          # Add ToolRegistry to supervision, wire extension tools
lib/familiar/execution/execution.ex  # Update Boundary exports: add ToolRegistry
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md — Addendum lines 1060-1076: ToolRegistry description and tool list]
- [Source: _bmad-output/planning-artifacts/architecture.md — Decision A5 lines 1822-1834: Harness core components]
- [Source: _bmad-output/planning-artifacts/epics.md — Story 5.2 lines 1266-1272]
- [Source: familiar/lib/familiar/execution/extension.ex — tool_registration type]
- [Source: familiar/lib/familiar/execution/extension_loader.ex — tools collection]
- [Source: familiar/lib/familiar/execution/hooks.ex — alter/3, event/2 API]
- [Source: familiar/lib/familiar/application.ex — extension loading flow]
- [Source: familiar/lib/familiar/roles/validator.ex — @mvp_tools list]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- `Familiar.Execution.ToolRegistry` GenServer: register/dispatch/list/get_tool/tool_schemas/register_builtins
- `dispatch/3` is the single chokepoint: `before_tool_call` alter → execute → `after_tool_call` event
- Tool crash isolation via try/rescue in `execute_tool/3`
- 10 core builtin stubs: read_file, write_file, delete_file, list_files, search_files, run_command, spawn_agent, monitor_agents, broadcast_status, signal_ready
- ExtensionLoader updated to tag tools with extension name (3-tuple → 4-tuple)
- Application.start wires ToolRegistry into supervision tree, registers builtins before extension tools
- Boundary updated: `Familiar.Execution` exports `[Extension, Hooks, ToolRegistry]`
- Test count: 696 → 712 (+16), 0 failures, Credo strict: 0 issues

### File List

- familiar/lib/familiar/execution/tool_registry.ex (new)
- familiar/lib/familiar/execution/execution.ex (modified — Boundary exports)
- familiar/lib/familiar/execution/extension_loader.ex (modified — 4-tuple tool tagging)
- familiar/lib/familiar/application.ex (modified — ToolRegistry supervision + builtin registration + extension tool wiring)
- familiar/test/familiar/execution/tool_registry_test.exs (new)
- familiar/test/familiar/execution/extension_loader_test.exs (modified — 4-tuple assertion)

### Change Log

- 2026-04-03: Implemented Story 5.2 — Tool Registry
