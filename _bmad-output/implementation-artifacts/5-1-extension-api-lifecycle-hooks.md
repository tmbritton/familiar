# Story 5.1: Extension API & Lifecycle Hooks

Status: done

## Story

As a developer building the harness,
I want an extension system with lifecycle hooks so that capabilities (tools, safety, knowledge) are pluggable,
So that the harness core stays thin and extensions can react to agent lifecycle events.

## Acceptance Criteria

### AC1: Extension Behaviour

**Given** the harness extension system is implemented
**When** a module implements `Familiar.Extension`
**Then** it must define these callbacks:
  - `name()` — returns a unique string name for the extension
  - `tools()` — returns a list of `{atom, function, String.t}` tool registrations
  - `hooks()` — returns a list of hook registrations (`%{hook: atom, handler: function, priority: integer, type: :alter | :event}`)
  - `child_spec(opts)` — returns a `Supervisor.child_spec()` or `nil` if no supervision needed
  - `init(opts)` — returns `:ok` or `{:error, term}` for extension-specific setup

### AC2: Alter Hook Pipeline

**Given** extensions register `before_tool_call` alter hooks at various priorities
**When** `Hooks.alter(:before_tool_call, payload, context)` is called
**Then** handlers run in priority order (lower priority number runs first)
**And** each handler can modify the payload (pass-through) or return `{:halt, reason}` to veto
**And** the pipeline returns `{:ok, possibly_modified_payload}` or `{:halt, reason}`

**Given** an alter hook handler raises an exception
**When** the pipeline processes that handler
**Then** the exception is caught, the handler is skipped, the unmodified payload continues through remaining handlers
**And** a warning is logged with the extension name and error

**Given** an alter hook handler exceeds the timeout (5 seconds)
**When** the pipeline processes that handler
**Then** the handler is killed, skipped, and the unmodified payload continues
**And** a warning is logged

**Given** a handler fails 3 consecutive times
**When** the circuit breaker triggers
**Then** the handler is disabled for subsequent calls until the extension is reloaded
**And** a warning is logged indicating the handler was circuit-broken

### AC3: Event Hook Dispatch

**Given** extensions register event hooks (e.g., `on_agent_complete`, `after_tool_call`)
**When** `Hooks.event(:on_agent_complete, payload)` is called
**Then** the event is broadcast via `Familiar.Activity` PubSub
**And** extension handlers subscribed to that event receive it
**And** a crash in one event handler does not affect core or other handlers (PubSub process isolation)

### AC4: Extension Loader

**Given** extensions are configured in application config
**When** `Application.start/2` runs
**Then** each extension module's `init/1` is called
**And** child specs are added to the supervision tree
**And** hooks are registered with `Familiar.Hooks`
**And** tool registrations are collected (available for Story 5.2 ToolRegistry)

**Given** an extension fails to initialize
**When** `init/1` returns `{:error, reason}`
**Then** a warning is logged with the extension name and error
**And** the extension is skipped (other extensions continue loading)
**And** the system does not crash

### AC5: MVP Hook Set

**Given** the hooks system is initialized
**Then** the following hooks are defined:
  - `on_startup` (event) — fired after all extensions loaded; Knowledge Store uses this to trigger codebase indexing
  - `on_agent_start` (event) — fired when AgentProcess initializes with a role; extensions can prepare per-agent state
  - `before_tool_call` (alter) — safety enforcement, arg validation
  - `after_tool_call` (event) — result logging, knowledge capture
  - `on_agent_complete` (event) — post-task hygiene, cleanup
  - `on_agent_error` (event) — error logging, failure analysis
  - `on_file_changed` (event) — knowledge store freshness; payload includes `change_type: :created | :modified | :deleted`
  - `on_shutdown` (event) — fired during graceful shutdown; cleanup, state persistence

### AC6: Test Coverage

**Given** the extension system is implemented
**When** `mix test` runs
**Then** alter pipeline ordering, veto, and pass-through are tested
**And** alter pipeline error handling: exception skip, timeout kill, circuit breaker activation are tested
**And** event dispatch isolation: handler crash does not affect other handlers
**And** extension loading: successful load, failed init skip, missing callback handling
**And** near-100% coverage on `Familiar.Extension`, `Familiar.Hooks`, and the extension loader

## Tasks / Subtasks

- [x] Task 1: Define `Familiar.Extension` behaviour (AC: 1)
  - [x] Create `lib/familiar/execution/extension.ex` — `Familiar.Extension` behaviour module
  - [x] Define `@callback name() :: String.t()`
  - [x] Define `@callback tools() :: [{atom(), function(), String.t()}]`
  - [x] Define `@callback hooks() :: [hook_registration()]`
  - [x] Define `@callback child_spec(keyword()) :: Supervisor.child_spec() | nil`
  - [x] Define `@callback init(keyword()) :: :ok | {:error, term()}`
  - [x] Define `@type hook_registration` typespec
  - [x] Add `@optional_callbacks [child_spec: 1]` — not all extensions need supervision
  - [x] Write tests: a module implementing the behaviour compiles and returns expected values

- [x] Task 2: Implement `Familiar.Hooks` GenServer (AC: 2, 3, 5)
  - [x] Create `lib/familiar/execution/hooks.ex` — `Familiar.Hooks` GenServer
  - [x] State: `%{alter_hooks: %{hook_name => [sorted_handlers]}, event_subscriptions: %{hook_name => [handlers]}, circuit_breaker: %{handler_key => failure_count}}`
  - [x] `register_alter_hook(hook, handler_fn, priority, extension_name)` — adds to sorted handler list
  - [x] `register_event_hook(hook, handler_fn, extension_name)` — subscribes Activity topic for the event
  - [x] `alter(hook, payload, context)` — runs alter pipeline: `Enum.reduce_while` over sorted handlers
  - [x] `event(hook, payload)` — broadcasts event via `Familiar.Activity`
  - [x] Each alter handler call: wrap in `Task.Supervisor.async_nolink` with 5s timeout
  - [x] Circuit breaker: track consecutive failures per handler key, disable after 3
  - [x] `reset_circuit_breaker(handler_key)` — re-enables a circuit-broken handler
  - [x] Event topic convention: `"hooks:#{hook_name}"` via Activity
  - [x] Write tests for alter pipeline: ordering, veto via `{:halt, reason}`, pass-through modification

- [x] Task 3: Alter pipeline error isolation (AC: 2)
  - [x] Test: handler that raises → caught, skipped, payload unmodified, warning logged
  - [x] Test: handler that times out (>5s) → killed, skipped, warning logged
  - [x] Test: 3 consecutive failures → circuit breaker activates, handler disabled
  - [x] Test: circuit breaker reset re-enables handler
  - [x] Use `capture_log` to verify warning messages

- [x] Task 4: Event dispatch (AC: 3)
  - [x] Implement event dispatch: broadcast via `Familiar.Activity.broadcast/2` with hook-specific topic
  - [x] Extension event handlers run in their own processes (PubSub subscriber isolation via Task.Supervisor)
  - [x] Test: event reaches subscribed handler
  - [x] Test: crashing event handler does not crash the Hooks GenServer or other handlers
  - [x] Test: multiple handlers for same event all receive it

- [x] Task 5: Extension loader (AC: 4)
  - [x] Create `lib/familiar/execution/extension_loader.ex` — `Familiar.Execution.ExtensionLoader`
  - [x] `load_extensions(extension_modules, opts)` — iterates configured modules, calls `init/1`, collects tools/hooks/child_specs
  - [x] Returns `{:ok, %{tools: [...], child_specs: [...], loaded: [...], failed: [...]}}`
  - [x] Failed extensions logged and skipped, not crashed
  - [x] Add extension loading to `Application.start/2` — read config, call loader, start child specs, register hooks
  - [x] After all extensions loaded: fire `Hooks.event(:on_startup, %{extensions: loaded_names})`
  - [x] Config key: `config :familiar, :extensions, [list of modules]` (default: `[]` for now; Stories 5.6/5.7 add defaults)
  - [x] Test: successful extension init, hooks registered, child_specs collected
  - [x] Test: extension with failing `init/1` — skipped, others still load

- [x] Task 6: Update Boundary and wire into supervision (AC: 4, 5)
  - [x] Update `Familiar.Execution` boundary: `exports: [Familiar.Extension, Familiar.Hooks]`
  - [x] Add `Familiar.Hooks` to supervision tree in `application.ex` (before extensions load)
  - [x] Ensure Hooks GenServer starts before any extension init runs
  - [x] Fire `Hooks.event(:on_shutdown, %{})` during graceful shutdown (in Daemon.Server terminate)

- [x] Task 7: Credo, formatting, full regression (AC: 6)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (694 tests, +21 new)
  - [x] Verify test count increment: 673 → 694

### Review Findings

- [x] [Review][Patch] child_specs from ExtensionLoader discarded in application.ex — fixed: start_extension_children/1 starts specs under Familiar.Supervisor
- [x] [Review][Patch] Event handlers receive inspect'd string instead of original payload map — fixed: event/2 broadcasts {:hook_event, hook, payload} directly via PubSub
- [x] [Review][Patch] Public API functions hardcode `__MODULE__` as GenServer name — intentional singleton design; tests use direct GenServer.call for isolation
- [x] [Review][Patch] No test for missing-callback validation — added test with module missing required callbacks
- [x] [Review][Patch] No test for child_spec collection through the loader — added test with extension returning child_spec
- [x] [Review][Defer] on_shutdown fires during OTP terminate — TaskSupervisor may already be stopped — deferred, OTP shutdown ordering
- [x] [Review][Defer] Duplicate extension registration accumulates handlers — deferred, no reload path exists yet
- [x] [Review][Defer] alter/3 uses :infinity GenServer timeout — deferred, MVP is sequential single-agent

## Dev Notes

### Architecture Constraints

- **Hexagonal architecture**: Extension behaviour follows the same pattern as `Familiar.Providers.LLM` — define callbacks, resolve implementations from config. This is the established project pattern.
- **Error tuple convention**: All public functions return `{:ok, result}` or `{:error, {atom_type, map_details}}`.
- **`use Boundary`**: `Familiar.Execution` already exists with `deps: [Familiar.Knowledge, Familiar.Work, Familiar.Files, Familiar.Providers]`. Update `exports` to include `Familiar.Extension` and `Familiar.Hooks`.
- **No Ecto/DB**: This context is purely in-memory GenServer state. No schemas, no migrations.
- **Logger for warnings**: Extension failures logged via `Logger.warning/1`.

### Existing Infrastructure to Build On

| What | Where | How It's Used |
|------|-------|--------------|
| `Familiar.Activity` | `lib/familiar/activity.ex` | PubSub broadcasting — `broadcast/2`, `subscribe/1`, `topic/1`. Already has event types: `:tool_call`, `:agent_complete`, `:agent_spawned`, etc. Event hooks piggyback on this. |
| `Phoenix.PubSub` | `application.ex` — `{Phoenix.PubSub, name: Familiar.PubSub}` | Already in supervision tree. Activity uses it. Event hooks use it via Activity. |
| `Familiar.Execution` | `lib/familiar/execution/execution.ex` | Skeleton context with Boundary declaration. Currently stub functions returning `{:error, {:not_implemented, %{}}}`. New modules go here. |
| Application config pattern | `config/config.exs`, `config/test.exs` | Behaviour port config: `config :familiar, Familiar.Providers.LLM, Module`. Extensions follow same pattern: `config :familiar, :extensions, [modules]`. |
| Mox + MockCase | `test/support/mocks.ex`, `test/support/mock_case.ex` | Mock definitions for behaviour ports. Extension tests don't need Mox — they test concrete implementations with stubbed callbacks. |
| `Task.Supervisor` | `application.ex` — `{Task.Supervisor, name: Familiar.TaskSupervisor}` | Already in supervision tree. Alter hook timeout can use `Task.Supervisor.async_nolink` for isolated handler execution. |

### Key Design Decisions

1. **Hooks GenServer, not ETS** — Hook registrations change infrequently (only on extension load/reload). A GenServer with sorted lists is simpler than ETS and allows the circuit breaker state to live in one place. The alter pipeline is called on every tool call, but the handler list is already sorted — iteration is O(n) where n is typically 1-3 handlers.

2. **`Task.async` with timeout for alter handlers** — Each alter handler is executed in a linked task with a 5-second timeout. This provides both exception isolation (`try/rescue`) and timeout enforcement. If the task exits abnormally, the pipeline skips the handler and continues. Use `Task.Supervisor.async_nolink(Familiar.TaskSupervisor, ...)` for full isolation.

3. **Event dispatch via Activity, not direct GenServer calls** — Event hooks are inherently fire-and-forget. Using `Familiar.Activity.broadcast/2` means event handlers run in their own subscriber processes. A crashing subscriber is isolated by PubSub — no impact on the Hooks GenServer or other subscribers. This matches the architecture Decision A5 design.

4. **Extension loader is a module function, not a GenServer** — Loading happens once at startup (and potentially on reload). A pure function `load_extensions/2` that returns collected registrations is simpler and more testable than a stateful process. The Application supervisor calls it and threads the results into Hooks registration and child spec startup.

5. **Circuit breaker is per-handler, not per-extension** — An extension might register multiple alter hooks. If one hook handler is broken, only that handler is disabled. Other handlers from the same extension continue working.

6. **`@optional_callbacks [child_spec: 1]`** — Many extensions (like Safety) don't need supervision children. Making `child_spec/1` optional avoids forcing them to return `nil`.

7. **MVP hook set is fixed** — The 8 hooks (`on_startup`, `on_agent_start`, `before_tool_call`, `after_tool_call`, `on_agent_complete`, `on_agent_error`, `on_file_changed`, `on_shutdown`) are defined in this story. `on_startup` fires after all extensions are loaded — the Knowledge Store extension (Story 5.7) will use this to trigger codebase indexing. `on_shutdown` fires during graceful shutdown for cleanup. Adding new hooks later is just adding a new atom. No registration restriction needed — any atom works as a hook name, but the MVP set documents what the harness actually broadcasts.

### Existing Code Patterns to Follow

```elixir
# Behaviour definition (from Familiar.Providers.LLM):
defmodule Familiar.Extension do
  @callback name() :: String.t()
  # ...
end

# Config-based DI (from config.exs):
config :familiar, :extensions, [
  Familiar.Extensions.Safety,
  Familiar.Extensions.KnowledgeStore
]

# Activity broadcasting (from activity.ex):
Activity.broadcast(scope_id, %Activity.Event{
  type: :tool_call,
  detail: "...",
  result: "...",
  timestamp: DateTime.utc_now()
})
```

### Previous Story Intelligence (4.5-2)

- **Test baseline**: 673 tests + 4 properties, 0 failures. Credo strict: 0 issues.
- **Boundary pattern**: `use Boundary, deps: [...], exports: [...]` on context facade modules.
- **The `Familiar.Execution` context exists** but is a stub. This story adds the first real modules under it.
- **Activity module** already defines event types that map to hook names (`:tool_call`, `:agent_complete`, etc.). Event hooks should use these same event types for consistency.

### Testing Standards

- `use ExUnit.Case, async: true` — Hooks GenServer tests need their own process per test (start in setup, stop in on_exit)
- No DataCase needed — no database access
- No Mox needed for the behaviour itself — test with concrete stub modules implementing `Familiar.Extension`
- Test the alter pipeline with inline anonymous functions or test modules, not mocks
- `capture_log` for verifying warning messages on errors, timeouts, circuit breakers
- For timeout tests: use a handler that does `Process.sleep(10_000)` to trigger the 5s timeout

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── execution.ex              # Existing — update Boundary exports
├── extension.ex              # NEW — Familiar.Extension behaviour
├── hooks.ex                  # NEW — Familiar.Hooks GenServer
└── extension_loader.ex       # NEW — Familiar.Execution.ExtensionLoader

test/familiar/execution/
├── extension_test.exs        # NEW — behaviour compliance tests
├── hooks_test.exs            # NEW — alter pipeline, event dispatch, error isolation
└── extension_loader_test.exs # NEW — loading, init failures, registration collection
```

Modified files:
```
lib/familiar/application.ex          # Add Hooks to supervision, extension loading
lib/familiar/execution/execution.ex  # Update Boundary exports
config/config.exs                    # Add :extensions config key (empty list default)
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md — Decision A5: Extension System & Lifecycle Hooks, lines 1727-1834]
- [Source: _bmad-output/planning-artifacts/epics.md — Epic 5, Story 5.1, lines 1258-1264]
- [Source: familiar/lib/familiar/activity.ex — PubSub infrastructure]
- [Source: familiar/lib/familiar/application.ex — current supervision tree]
- [Source: familiar/lib/familiar/execution/execution.ex — existing Execution context stub]
- [Source: familiar/config/config.exs — behaviour port configuration pattern]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- `Familiar.Extension` behaviour with 5 callbacks (name, tools, hooks, child_spec, init), `child_spec` optional
- `Familiar.Hooks` GenServer: alter pipeline with priority ordering, `{:halt, reason}` veto, Task.Supervisor.async_nolink isolation, 5s timeout, circuit breaker (3 consecutive failures)
- Event dispatch via Activity PubSub with crash-isolated Task.Supervisor children
- `Familiar.Execution.ExtensionLoader` loads from config, skips failed extensions, collects tools/hooks/child_specs
- Wired into Application.start/2: Hooks GenServer in supervision tree, extensions loaded after supervisor starts, `on_startup` event fired after load
- `on_shutdown` event fired from Daemon.Server terminate
- Config key `config :familiar, :extensions, []` added to config.exs
- Boundary updated: `Familiar.Execution` exports `[Familiar.Extension, Familiar.Hooks]`
- 8 MVP hooks: on_startup, on_agent_start, before_tool_call, after_tool_call, on_agent_complete, on_agent_error, on_file_changed, on_shutdown
- Test count: 673 → 694 (+21), 0 failures, Credo strict: 0 issues

### File List

- familiar/lib/familiar/execution/extension.ex (new)
- familiar/lib/familiar/execution/hooks.ex (new)
- familiar/lib/familiar/execution/extension_loader.ex (new)
- familiar/lib/familiar/execution/execution.ex (modified — Boundary exports)
- familiar/lib/familiar/application.ex (modified — Hooks supervision + extension loading)
- familiar/lib/familiar/daemon/server.ex (modified — on_shutdown event)
- familiar/config/config.exs (modified — :extensions config key)
- familiar/test/familiar/execution/extension_test.exs (new)
- familiar/test/familiar/execution/hooks_test.exs (new)
- familiar/test/familiar/execution/extension_loader_test.exs (new)

### Change Log

- 2026-04-03: Implemented Story 5.1 — Extension API & Lifecycle Hooks
