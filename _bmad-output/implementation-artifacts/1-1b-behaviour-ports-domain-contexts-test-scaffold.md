# Story 1.1b: Behaviour Ports, Domain Contexts & Test Scaffold

Status: done

## Story

As a developer,
I want hexagonal architecture ports, domain-driven contexts, and test infrastructure in place,
so that all business logic is testable through behaviour mocks and context boundaries are enforced.

## Acceptance Criteria

1. **6 Behaviour Ports Defined:** LLM, FileSystem, Embedder, Shell, Notifications, Clock — each with callback specifications
2. **Mox Mocks Configured:** Mox mock definitions for all 6 behaviours in `config/test.exs`
3. **ExUnit Case Templates:** Case templates for sandbox + mock setups available in `test/support/`
4. **Test Factories:** Factories for knowledge entries, tasks, and specs created in `test/support/`
5. **Test Coverage Reporting:** Coverage enabled with mid-high 90s% CI threshold
6. **7 Domain Context Directories:** knowledge/, work/, planning/, execution/, files/, providers/, cli/ under `lib/familiar/`
7. **7 Public API Facade Modules:** Each context has a stub facade module with `@moduledoc` and function specs
8. **Boundary Package Configured:** `boundary` compile-time context boundary enforcement working
9. **Error Module:** `Familiar.Error` with `recoverable?/1` policy function
10. **Compilation Clean:** `mix compile --warnings-as-errors` passes
11. **Boundary Checks Pass:** `boundary` compile-time checks pass
12. **Tests Pass:** `mix test` passes with Ecto sandbox and Mox mocks properly configured

## Tasks / Subtasks

- [x] Task 1: Create 6 behaviour port modules (AC: #1)
  - [x] `lib/familiar/providers/llm.ex` — `Familiar.Providers.LLM` behaviour with callbacks: `chat/2`, `stream_chat/2`
  - [x] `lib/familiar/knowledge/embedder.ex` — `Familiar.Knowledge.Embedder` behaviour with callback: `embed/1`
  - [x] `lib/familiar/system/file_system.ex` — `Familiar.System.FileSystem` behaviour with callbacks: `read/1`, `write/2`, `stat/1`, `delete/1`, `ls/1`
  - [x] `lib/familiar/system/shell.ex` — `Familiar.System.Shell` behaviour with callback: `cmd/3`
  - [x] `lib/familiar/system/notifications.ex` — `Familiar.System.Notifications` behaviour with callback: `notify/2`
  - [x] `lib/familiar/system/clock.ex` — `Familiar.System.Clock` behaviour with callback: `now/0`
- [x] Task 2: Configure Mox mocks (AC: #2)
  - [x] Add Mox.defmock for all 6 behaviours in `test/support/mocks.ex`
  - [x] Configure application env in `config/test.exs` to use mock implementations
  - [x] Verify mocks compile and are available in test env
- [x] Task 3: Create ExUnit case templates (AC: #3)
  - [x] `test/support/data_case.ex` — verified, sandbox works
  - [x] `test/support/mock_case.ex` — Mox verify_on_exit via setup callback
  - [x] Case templates available via `use Familiar.MockCase`
- [x] Task 4: Create test factories (AC: #4)
  - [x] `test/support/factory.ex` — `build_knowledge_entry/1`, `build_task/1`, `build_spec/1`
  - [x] Factories return plain maps (schemas don't exist yet)
- [x] Task 5: Configure test coverage (AC: #5)
  - [x] Added `test_coverage: [threshold: 90]` to `mix.exs` project config
- [x] Task 6: Create domain context directories and stub facades (AC: #6, #7)
  - [x] `lib/familiar/knowledge/knowledge.ex` — `Familiar.Knowledge` with `use Boundary`
  - [x] `lib/familiar/work/work.ex` — `Familiar.Work` with `use Boundary`
  - [x] `lib/familiar/planning/planning.ex` — `Familiar.Planning` with `use Boundary`
  - [x] `lib/familiar/execution/execution.ex` — `Familiar.Execution` with `use Boundary`
  - [x] `lib/familiar/files/files.ex` — `Familiar.Files` with `use Boundary`
  - [x] `lib/familiar/providers/providers.ex` — `Familiar.Providers` with `use Boundary`
  - [x] `lib/familiar/cli/cli.ex` — `Familiar.CLI` with `use Boundary`
  - [x] Each stub has `@moduledoc`, `@spec` declarations, returns `{:error, :not_implemented}`
- [x] Task 7: Create error module (AC: #9)
  - [x] `lib/familiar/error.ex` — `recoverable?/1` with pattern matching on all error types
  - [x] `test/familiar/error_test.exs` — 6 tests covering all error types + default
- [x] Task 8: Configure boundary package (AC: #8, #11)
  - [x] `use Boundary` with `deps` and `exports` on all 7 context facades
  - [x] `mix compile --warnings-as-errors` passes with boundary checks
- [x] Task 9: Write tests for behaviour ports (AC: #1, #12)
  - [x] `test/familiar/providers/llm_test.exs` — 3 tests (chat, stream, error)
  - [x] `test/familiar/system/system_test.exs` — 7 tests (all 4 FileSystem + Shell + Notifications + Clock)
  - [x] `test/familiar/knowledge/embedder_test.exs` — 2 tests (embed, error)
- [x] Task 10: Final verification (AC: #10, #11, #12)
  - [x] `mix compile --warnings-as-errors` — passes
  - [x] `mix test` — 27 tests, 0 failures
  - [x] `mix format --check-formatted` — passes
  - [x] `mix credo --strict` — no issues

## Dev Notes

### Architecture Compliance

**Source:** [architecture.md — Testing Architecture, Extensibility Architecture]

**CRITICAL DISTINCTION:** This story creates the **6 testing ports** (external system boundaries, built from day one). These are SEPARATE from the **6 extensibility behaviours** (Agent, Tool, Validator, Extractor, PromptStrategy, WorkflowExecutor) which are anticipated but NOT built yet — they emerge from working code later.

### 6 Behaviour Port Definitions

**Source:** [architecture.md — Testing Architecture, lines 515-524]

| Port (Behaviour) | Module Path | Callbacks |
|---|---|---|
| `Familiar.Providers.LLM` | `lib/familiar/providers/llm.ex` | `chat(messages, opts)`, `stream_chat(messages, opts)` |
| `Familiar.Knowledge.Embedder` | `lib/familiar/knowledge/embedder.ex` | `embed(text)` |
| `Familiar.System.FileSystem` | `lib/familiar/system/file_system.ex` | `read(path)`, `write(path, content)`, `stat(path)`, `delete(path)`, `ls(path)` |
| `Familiar.System.Shell` | `lib/familiar/system/shell.ex` | `cmd(command, args, opts)` |
| `Familiar.System.Notifications` | `lib/familiar/system/notifications.ex` | `notify(title, body)` |
| `Familiar.System.Clock` | `lib/familiar/system/clock.ex` | `now()` |

**Callback return types follow the error tuple convention:**
- `{:ok, result}` for success
- `{:error, {atom_type, map_details}}` for failure

### 7 Domain Context Facades

**Source:** [architecture.md — Project Structure, lines 759-808]

Each facade is a stub — `@moduledoc` describing the context's purpose, `@spec` for each public function, all returning `{:error, :not_implemented}`. Business logic is implemented in their respective epics.

| Context | Facade Module | Key Functions (stubs) |
|---|---|---|
| knowledge/ | `Familiar.Knowledge` | `search/1`, `fetch_entry/1`, `store/1`, `health/0` |
| work/ | `Familiar.Work` | `fetch_task/1`, `list_tasks/1`, `update_status/2` |
| planning/ | `Familiar.Planning` | `start_plan/1`, `respond/2`, `get_spec/1` |
| execution/ | `Familiar.Execution` | `dispatch/1`, `cancel/1`, `status/0` |
| files/ | `Familiar.Files` | `write/3`, `rollback_task/1`, `pending_conflicts/0` |
| providers/ | `Familiar.Providers` | `chat/2`, `stream_chat/2`, `embed/1` |
| cli/ | `Familiar.CLI` | `main/1` |

### Error Module

**Source:** [architecture.md — Error Handling Convention, lines 568-583]

```elixir
defmodule Familiar.Error do
  def recoverable?({:provider_unavailable, _}), do: true
  def recoverable?({:file_conflict, _}), do: false
  def recoverable?({:validation_failed, _}), do: true
  def recoverable?({:not_found, _}), do: false
  def recoverable?({:invalid_config, _}), do: false
  def recoverable?(_), do: false
end
```

### Boundary Configuration

**Source:** [architecture.md — Context Boundary Enforcement, line 731]

Each context facade module uses `use Boundary` to declare its dependencies and exports. The `boundary` package enforces at compile time that contexts don't reach into each other's internals.

Example:
```elixir
defmodule Familiar.Knowledge do
  use Boundary, deps: [Familiar.Providers], exports: []
  # ...
end
```

The `cli/` context depends on NO other contexts directly — it's an HTTP client of the daemon, not a business domain.

### Mox Configuration Pattern

**Source:** [architecture.md — Testing Architecture]

In `test/support/mocks.ex`:
```elixir
Mox.defmock(Familiar.Providers.LLMMock, for: Familiar.Providers.LLM)
Mox.defmock(Familiar.Knowledge.EmbedderMock, for: Familiar.Knowledge.Embedder)
Mox.defmock(Familiar.System.FileSystemMock, for: Familiar.System.FileSystem)
Mox.defmock(Familiar.System.ShellMock, for: Familiar.System.Shell)
Mox.defmock(Familiar.System.NotificationsMock, for: Familiar.System.Notifications)
Mox.defmock(Familiar.System.ClockMock, for: Familiar.System.Clock)
```

In `config/test.exs`:
```elixir
config :familiar, Familiar.Providers.LLM, Familiar.Providers.LLMMock
config :familiar, Familiar.Knowledge.Embedder, Familiar.Knowledge.EmbedderMock
# ... etc for all 6
```

Production modules resolve via `Application.get_env(:familiar, Familiar.Providers.LLM)` — configured in `config/config.exs` or `config/prod.exs` to point to real adapters.

### What NOT to Do in This Story

- **Do NOT implement business logic** in the facade stubs — they return `{:error, :not_implemented}`
- **Do NOT create Ecto schemas** — schemas are created in their respective epics
- **Do NOT create the 6 extensibility behaviours** (Agent, Tool, Validator, etc.) — those emerge from working code later
- **Do NOT create production adapters** for the behaviours — that's Story 1.2 (providers) and later stories
- **Do NOT create migrations** — schema migrations belong to their respective epics

### Previous Story Learnings (from Story 1.1a)

- sqlite-vec vectors use JSON array strings, not binary encoding
- Phoenix 1.8.5 generates with daisyUI + Tailwind 4 — all stripped
- Credo `.credo.exs` must have `strict: true` (was generated as `false`)
- `async: true` doesn't work with sqlite-vec virtual tables — use `async: false` for vec_test

### Project Structure After This Story

```
lib/familiar/
├── application.ex           # (from 1.1a)
├── repo.ex                  # (from 1.1a)
├── error.ex                 # NEW — recoverable?/1
├── knowledge/
│   ├── knowledge.ex         # NEW — public API stub
│   └── embedder.ex          # NEW — behaviour definition
├── work/
│   └── work.ex              # NEW — public API stub
├── planning/
│   └── planning.ex          # NEW — public API stub
├── execution/
│   └── execution.ex         # NEW — public API stub
├── files/
│   └── files.ex             # NEW — public API stub
├── providers/
│   ├── providers.ex         # NEW — public API stub
│   └── llm.ex               # NEW — behaviour definition
├── cli/
│   └── cli.ex               # NEW — public API stub
└── system/
    ├── file_system.ex       # NEW — behaviour definition
    ├── shell.ex             # NEW — behaviour definition
    ├── notifications.ex     # NEW — behaviour definition
    └── clock.ex             # NEW — behaviour definition

test/
├── support/
│   ├── data_case.ex         # (from 1.1a, verified)
│   ├── mock_case.ex         # NEW — Mox verify_on_exit template
│   ├── mocks.ex             # NEW — 6 Mox.defmock definitions
│   └── factory.ex           # NEW — test factories
├── familiar/
│   ├── repo_test.exs        # (from 1.1a)
│   ├── error_test.exs       # NEW — recoverable?/1 tests
│   ├── providers/
│   │   └── llm_test.exs     # NEW — LLM mock verification
│   ├── knowledge/
│   │   └── embedder_test.exs # NEW — embedder mock verification
│   └── system/
│       └── system_test.exs  # NEW — system mocks verification
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Testing Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Extensibility Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Error Handling Convention]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1b]
- [Source: _bmad-output/implementation-artifacts/1-1a-phoenix-project-setup-database-foundation.md#Completion Notes]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- `Mox.verify_on_exit!` cannot be called as a module-level setup — must be wrapped in a `defp` and used via `setup :verify_on_exit!`
- `mix format` auto-fixed long `use Boundary` line in execution.ex
- Credo caught alias ordering in system_test.exs (alphabetical required)

### Completion Notes List

- 6 behaviour ports created with full callback specs and @doc
- 6 Mox mocks defined and configured in test.exs
- 7 domain context facades with `use Boundary`, `@moduledoc`, `@spec` stubs
- Error module with `recoverable?/1` and 6 tests
- MockCase template with verify_on_exit
- Factory module with 3 builder functions (maps, not schemas)
- Test coverage threshold at 90% configured
- 27 tests total, 0 failures

### File List

- lib/familiar/providers/llm.ex (new — LLM behaviour)
- lib/familiar/knowledge/embedder.ex (new — Embedder behaviour)
- lib/familiar/system/file_system.ex (new — FileSystem behaviour)
- lib/familiar/system/shell.ex (new — Shell behaviour)
- lib/familiar/system/notifications.ex (new — Notifications behaviour)
- lib/familiar/system/clock.ex (new — Clock behaviour)
- lib/familiar/knowledge/knowledge.ex (new — Knowledge facade stub)
- lib/familiar/work/work.ex (new — Work facade stub)
- lib/familiar/planning/planning.ex (new — Planning facade stub)
- lib/familiar/execution/execution.ex (new — Execution facade stub)
- lib/familiar/files/files.ex (new — Files facade stub)
- lib/familiar/providers/providers.ex (new — Providers facade stub)
- lib/familiar/cli/cli.ex (new — CLI facade stub)
- lib/familiar/error.ex (new — recoverable?/1)
- test/support/mocks.ex (new — 6 Mox.defmock)
- test/support/mock_case.ex (new — ExUnit case template)
- test/support/factory.ex (new — test factories)
- test/familiar/error_test.exs (new — 6 tests)
- test/familiar/providers/llm_test.exs (new — 3 tests)
- test/familiar/knowledge/embedder_test.exs (new — 2 tests)
- test/familiar/system/system_test.exs (new — 7 tests)
- config/test.exs (modified — mock config)
- mix.exs (modified — test_coverage threshold)
