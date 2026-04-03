# Story 5.6: Safety Extension

Status: done

## Story

As a developer building the harness,
I want a default extension that vetoes dangerous tool calls via the alter hook pipeline,
So that agents cannot escape the project directory, write to `.git/`, or execute arbitrary commands.

## Acceptance Criteria

### AC1: Extension Module Implementing `Familiar.Extension` Behaviour

**Given** the `Familiar.Extension` behaviour exists (Story 5.1)
**When** `Familiar.Extensions.Safety` is implemented
**Then** it implements all required callbacks: `name/0`, `tools/0`, `hooks/0`, `init/1`
**And** `name/0` returns `"safety"`
**And** `tools/0` returns `[]` (safety operates via hooks only, no tools)
**And** `hooks/0` returns a single `before_tool_call` alter hook at priority 1
**And** `init/1` accepts a keyword list of options (`:project_dir`, `:allowed_commands`, `:extra_rules`) and returns `:ok`

### AC2: Path Validation (Project Directory Sandboxing)

**Given** the safety extension is active
**When** a tool call includes a `path` argument
**Then** the path is resolved to its canonical form (symlinks resolved via `File.stat/1` or parent-dir check)
**And** it must be within the project directory (or a subdirectory)
**And** paths containing `..` traversal that escape the project directory are rejected
**And** absolute paths outside the project directory are rejected
**And** rejection returns `{:halt, "path_outside_project: <path>"}`

### AC3: `.git/` Directory Protection

**Given** the safety extension is active
**When** a tool call targets a path inside the `.git/` directory
**And** the tool is a write or delete operation (`:write_file`, `:delete_file`)
**Then** it is rejected with `{:halt, "git_dir_protected: <path>"}`
**And** read operations on `.git/` are allowed (agents can read `.gitignore`, etc.)

### AC4: Shell Command Allow-List

**Given** the safety extension is active
**When** a `:run_command` tool call is dispatched
**Then** the command is checked against a configurable allow-list
**And** the default allow-list is: `["mix test", "mix format", "mix credo", "mix compile", "mix deps.get"]`
**And** commands not on the allow-list are rejected with `{:halt, "command_not_allowed: <cmd>"}`
**And** commands are matched by prefix (e.g., `"mix test"` allows `"mix test test/my_test.exs"`)
**And** the allow-list is configurable via `:allowed_commands` option

### AC5: Delete Scope Restriction

**Given** the safety extension is active
**When** a `:delete_file` tool call is dispatched
**Then** only files within the project directory are deletable (covered by AC2)
**And** deletion of directories is rejected with `{:halt, "directory_delete_blocked: <path>"}`
**And** `.git/` files cannot be deleted (covered by AC3)

### AC6: Passthrough for Safe Operations

**Given** the safety extension is active
**When** a tool call passes all safety checks
**Then** the payload is returned unmodified via `{:ok, payload}`
**And** no args are modified (safety only vetoes, never transforms)
**And** tools not subject to safety rules (e.g., `:search_context`, `:monitor_agents`) pass through without checks

### AC7: Configuration via Options

**Given** the safety extension is loaded
**When** `init/1` is called with options
**Then** `:project_dir` sets the sandbox root (default: `File.cwd!/0`)
**And** `:allowed_commands` overrides the default command allow-list
**And** configuration is stored in a named ETS table or Agent for handler access
**And** the config is accessible to the `before_tool_call` handler function

### AC8: Test Coverage

**Given** `Familiar.Extensions.Safety` is implemented
**When** `mix test` runs
**Then** tests cover: path validation (valid, traversal, absolute, symlink), `.git/` protection (write blocked, read allowed), command allow-list (allowed, blocked, prefix match), delete restrictions (file ok, directory blocked), passthrough for safe tools, custom config
**And** tests use the alter hook pipeline directly (register hook, call `Hooks.alter/3`)
**And** Credo strict passes with 0 issues
**And** no regressions in existing test suite (788 tests + 5 properties baseline)

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Extensions.Safety` module (AC: 1, 7)
  - [x] Create `lib/familiar/extensions/safety.ex`
  - [x] Implement `Familiar.Extension` behaviour callbacks
  - [x] `name/0` → `"safety"`
  - [x] `tools/0` → `[]`
  - [x] `hooks/0` → `[%{hook: :before_tool_call, handler: &check_tool_call/2, priority: 1, type: :alter}]`
  - [x] `init/1` — store config in named ETS table (`:familiar_safety_config`)
  - [x] State: project_dir, allowed_commands list

- [x] Task 2: Implement `check_tool_call/2` handler (AC: 2, 3, 4, 5, 6)
  - [x] Main handler dispatches to per-tool validators based on `payload.tool`
  - [x] `:write_file` → validate path (AC2) + git protection (AC3)
  - [x] `:delete_file` → validate path (AC2) + git protection (AC3) + directory check (AC5)
  - [x] `:run_command` → command allow-list check (AC4)
  - [x] `:read_file`, `:list_files`, `:search_files` → validate path only (AC2), allow `.git/` reads
  - [x] Other tools (`:search_context`, `:store_context`, `:spawn_agent`, etc.) → passthrough (AC6)
  - [x] Return `{:ok, payload}` for allowed, `{:halt, reason}` for blocked

- [x] Task 3: Path validation logic (AC: 2)
  - [x] `validate_path/2` — takes path string and project_dir
  - [x] Expand path with `Path.expand/2` to resolve `..` and relative segments
  - [x] Check `String.starts_with?(expanded, project_dir <> "/")` after expansion
  - [x] Handle edge case: path equals project_dir itself (allowed)
  - [x] Return `:ok` or `{:halt, reason}`

- [x] Task 4: Git directory protection (AC: 3)
  - [x] `in_git_dir?/2` — checks if path is inside `.git/` directory
  - [x] Use `Path.relative_to/2` then check if first component is `.git`
  - [x] Only blocks write/delete, not read operations

- [x] Task 5: Command allow-list (AC: 4)
  - [x] `check_command_allowed/2` — checks command against allow-list
  - [x] Match by prefix: `Enum.any?(allowed, &String.starts_with?(command, &1))`
  - [x] Default list: `["mix test", "mix format", "mix credo", "mix compile", "mix deps.get"]`

- [x] Task 6: Delete restrictions (AC: 5)
  - [x] Check if target is a directory via `File.dir?/1`
  - [x] Block directory deletion (only file deletion allowed)

- [x] Task 7: Add to extension config in `config/config.exs` (AC: 1)
  - [x] Add `Familiar.Extensions.Safety` to `config :familiar, :extensions` list
  - [x] Ensure it loads at application startup via ExtensionLoader
  - [x] Override to `[]` in test.exs (tests register hooks manually)

- [x] Task 8: Boundary configuration
  - [x] Create `Familiar.Extensions` boundary module with deps on `Familiar.Execution`
  - [x] Export `Familiar.Extensions.Safety`

- [x] Task 9: Tests (AC: 8)
  - [x] Create `test/familiar/extensions/safety_test.exs`
  - [x] Test: path within project dir allowed
  - [x] Test: path with `..` traversal blocked
  - [x] Test: absolute path outside project blocked
  - [x] Test: `.git/` write blocked (single and nested paths)
  - [x] Test: `.git/` read allowed (e.g., `.git/config`)
  - [x] Test: `.gitignore` write allowed (not inside `.git/`)
  - [x] Test: allowed command passes
  - [x] Test: blocked command rejected
  - [x] Test: command prefix matching works
  - [x] Test: file delete allowed
  - [x] Test: directory delete blocked
  - [x] Test: passthrough for non-file tools (6 tools tested)
  - [x] Test: custom allowed_commands config
  - [x] Test: custom project_dir config
  - [x] Test: handler returns `{:ok, payload}` unmodified on pass
  - [x] Test: hooks alter pipeline integration test

- [x] Task 10: Credo, formatting, full regression (AC: 8)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (826 tests + 5 properties)

### Review Findings

- [x] [Review][Decision] Command allow-list bypass via prefix injection — added word-boundary check: command must equal prefix or continue with a space. Best-effort gate; real security is execution environment. Added 5 tests (semicolon injection, && injection, exact match, nil command, missing key)
- [x] [Review][Decision] Symlinks not resolved — `Path.expand/2` is lexical only. Deferred to security hardening story — symlink resolution is complex (target may not exist for new files), and this was already flagged in Story 5.5 review
- [x] [Review][Decision] `:extra_rules` option — removed from AC1. Speculative; no current consumer. Will add when needed
- [x] [Review][Patch] ETS table changed from `:public` to `:protected` — owner (init caller) writes, handler Tasks read [safety.ex:73]
- [x] [Review][Patch] Path expansion centralized — `check` now expands path once and threads expanded path through `validate_path`, `check_git_protection`, and `check_delete_restrictions`. Eliminates raw-path bugs [safety.ex:94-105]
- [x] [Review][Patch] `run_command` nil guard — `|| ""` + `to_string/1` fallback prevents crash on nil/non-string command args [safety.ex:109-110]
- [x] [Review][Patch] Integration test uses `Safety.hooks/0` contract — registers hook via the hooks/0 return value, validating the actual registration shape [safety_test.exs]
- [x] [Review][Defer] ETS race condition on concurrent `init/1` — check-then-delete-then-create is not atomic. Concurrent init calls could crash. Unlikely in practice (init called once at startup) — deferred to hardening story
- [x] [Review][Defer] `load_config/0` crash on missing ETS table — pattern match raises if init never called. Handler failure would be caught by Hooks circuit breaker, silently disabling safety. Defensive check deferred
- [x] [Review][Defer] ToolRegistry GenServer blocks during `Hooks.alter` call — serializes all tool dispatches through single GenServer, each holding lock up to 5s if handler is slow — deferred to performance story
- [x] [Review][Defer] Hooks mailbox growth under rapid event fire — no back-pressure on event handler dispatch — deferred to resilience story
- [x] [Review][Defer] Unregistered hook type silently ignored in ExtensionLoader — hook with invalid type falls through case with no error — deferred
- [x] [Review][Defer] `execute_tool` in ToolRegistry rescue doesn't catch OTP exits — tool functions that call `:erlang.exit/1` would crash the GenServer — deferred

## Dev Notes

### Architecture Constraints

- **Extension, NOT core** — Safety is a default extension, not harness infrastructure. It loads via `ExtensionLoader` at startup, not the supervision tree. [Source: architecture.md line 1796-1801, epics.md]
- **Priority 1 on `before_tool_call`** — Safety must run first in the alter pipeline. Priority 1 (lowest = first). All other extension hooks should use priority >= 50. [Source: architecture.md line 1757-1770]
- **Hooks only, no tools** — Safety has no tools of its own. It operates entirely through the `before_tool_call` alter hook. [Source: architecture.md line 1796-1801]
- **Veto via `{:halt, reason}`** — The alter pipeline stops immediately on `{:halt, reason}`. `ToolRegistry.dispatch/3` converts this to `{:error, {:vetoed, reason}}`. [Source: hooks.ex, tool_registry.ex]
- **No child_spec needed** — Safety has no supervised processes. Config stored in ETS.

### Alter Hook Handler Contract

The `before_tool_call` alter handler receives:
```elixir
# payload (first arg)
%{tool: atom(), args: map()}

# context (second arg)
%{agent_id: String.t(), role: String.t(), conversation_id: String.t()}

# Must return one of:
{:ok, payload}       # Allow — pass unmodified payload to next handler
{:halt, reason}      # Veto — stop pipeline, tool call is blocked
```

Handler runs inside `Task.Supervisor.async_nolink` with 5-second timeout. Crashes are caught by circuit breaker (3 consecutive failures → handler disabled). See `Hooks.execute_alter_handler/3`.

### Config Storage Pattern

Use a named ETS table for handler-accessible config:
```elixir
def init(opts) do
  project_dir = Keyword.get_lazy(opts, :project_dir, &File.cwd!/0)
  allowed_commands = Keyword.get(opts, :allowed_commands, @default_allowed_commands)

  table = :ets.new(:familiar_safety_config, [:set, :named_table, :public, read_concurrency: true])
  :ets.insert(table, {:project_dir, project_dir})
  :ets.insert(table, {:allowed_commands, allowed_commands})
  :ok
end
```

This avoids needing a GenServer — the handler function can read config directly from ETS during alter pipeline execution.

### Tool-to-Check Mapping

| Tool | Path Check | Git Check | Command Check | Delete Check |
|------|-----------|-----------|---------------|-------------|
| `:write_file` | Yes | Yes (block) | — | — |
| `:delete_file` | Yes | Yes (block) | — | Yes |
| `:read_file` | Yes | Allow | — | — |
| `:list_files` | Yes | Allow | — | — |
| `:search_files` | Yes | Allow | — | — |
| `:run_command` | — | — | Yes | — |
| `:spawn_agent` | — | — | — | — |
| `:monitor_agents` | — | — | — | — |
| `:broadcast_status` | — | — | — | — |
| `:signal_ready` | — | — | — | — |
| `:search_context` | — | — | — | — |
| `:store_context` | — | — | — | — |

### Path Validation Strategy

```elixir
defp validate_path(path, project_dir) do
  expanded = Path.expand(path, project_dir)

  if String.starts_with?(expanded, project_dir <> "/") or expanded == project_dir do
    {:ok, expanded}
  else
    {:halt, "path_outside_project: #{path}"}
  end
end
```

Key: use `Path.expand/2` with project_dir as base for relative paths. This naturally handles `..` traversal. Compare expanded result against project_dir prefix.

### Test Strategy

Tests should exercise the handler directly through the Hooks alter pipeline — not through full tool dispatch (which would need tool implementations). Pattern:

```elixir
# Setup: register the safety handler
Safety.init(project_dir: tmp_dir)

Hooks.register_alter_hook(
  :before_tool_call,
  &Safety.check_tool_call/2,
  1,
  "safety"
)

# Test: valid path passes
payload = %{tool: :write_file, args: %{path: Path.join(tmp_dir, "foo.ex")}}
assert {:ok, ^payload} = Hooks.alter(:before_tool_call, payload, %{})

# Test: traversal blocked
payload = %{tool: :write_file, args: %{path: Path.join(tmp_dir, "../../../etc/passwd")}}
assert {:halt, "path_outside_project:" <> _} = Hooks.alter(:before_tool_call, payload, %{})
```

Use `System.tmp_dir!/0` for isolated test directories. Clean up ETS table in `on_exit` callback.

### Existing Patterns to Follow

- **Extension implementation**: See test fixtures in `test/familiar/execution/extension_test.exs` — `GoodExtension` module pattern
- **Alter hook registration**: See `hooks_test.exs` — register + alter + assert pattern
- **Boundary exports**: Add to `Familiar.Execution` boundary exports list in `execution.ex`
- **Application config**: See `config/config.exs` — add to `:extensions` list

### Previous Story Intelligence (Story 5.5)

- FileWatcher used named ETS for config in some patterns — but settled on GenServer state. Safety should use ETS since the handler fn runs in a Task (no GenServer state access).
- Component-based path matching (from `ignored?/2`) is a good pattern for `.git/` detection — use `Path.split/1` and check first component.
- Test baseline: 788 tests + 5 properties, 0 failures
- Credo strict: 0 issues
- Review finding from 5.5: symlinks outside project_dir bypass checks — Safety extension should expand paths canonically

### Deferred Items (NOT in scope)

- **Secret detection** — Architecture mentions secret detection in safety checks. This requires scanning tool args for patterns (API keys, passwords). Complex enough to warrant its own story or subtask of a hardening story. Defer.
- **TOML config** — Architecture mentions `.familiar/config.toml` `[safety]` section. No TOML parser exists yet. Use application env / init opts for now.
- **Role-based permission escalation** — Architecture says "A role file cannot escalate permissions." Full role-permission matrix is future work. For now, safety rules apply uniformly to all agents.
- **`intended_files` list enforcement** — Architecture mentions agents should warn (not block) when writing outside intended files. This is an AgentProcess-level feature, not a safety extension concern.

### Project Structure Notes

New files:
```
lib/familiar/extensions/
├── safety.ex              # NEW — Safety extension module

test/familiar/extensions/
├── safety_test.exs        # NEW — Safety extension tests
```

Modified files:
```
config/config.exs                           # MODIFIED — add Safety to :extensions list
lib/familiar/execution/execution.ex         # MODIFIED — add Safety to boundary exports (if needed)
```

### References

- [Source: architecture.md line 1803-1811 — Safety as extension with priority 1]
- [Source: architecture.md line 1757-1770 — Alter pipeline execution flow]
- [Source: architecture.md line 1796-1801 — Default extensions table (Safety has no tools, hooks only)]
- [Source: architecture.md line 1727-1747 — Extension behaviour definition]
- [Source: architecture.md line 1499-1501 — Skills define intent, safety enforces permission]
- [Source: architecture.md line 1723 — Tool implementations enforce safety regardless of role]
- [Source: epics.md line 1298-1304 — Story 5.6 scope definition]
- [Source: hooks.ex — alter pipeline, circuit breaker, handler timeout]
- [Source: tool_registry.ex — dispatch flow, run_before_hook, {:vetoed, reason}]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Safety extension implementing `Familiar.Extension` behaviour with `before_tool_call` alter hook at priority 1
- Config stored in named ETS table (`:familiar_safety_config`) for handler access from Task context
- Path validation via `Path.expand/2` with project_dir as base — handles `..` traversal and absolute paths
- `.git/` protection using `Path.split` component matching — blocks write/delete, allows read
- `.gitignore` in project root correctly NOT blocked (not inside `.git/` directory)
- Shell command allow-list with prefix matching — default: mix test/format/credo/compile/deps.get
- Delete restriction blocks directory deletion via `File.dir?/1`
- Non-file tools (search_context, spawn_agent, etc.) pass through without checks
- Tool args support both atom and string keys for `path`/`command` fields
- ETS table re-initialization on repeated `init/1` calls (safe for test reuse)
- Extensions disabled in test env (`config :familiar, :extensions, []`) to avoid startup load issues
- Credo strict: 0 issues (fixed redundant `with` clause)
- 38 new tests; 826 total tests + 5 properties, 0 failures, 0 regressions

### File List

- `familiar/lib/familiar/extensions/safety.ex` — NEW: Safety extension module
- `familiar/lib/familiar/extensions/extensions.ex` — NEW: Extensions boundary module
- `familiar/test/familiar/extensions/safety_test.exs` — NEW: 38 safety extension tests
- `familiar/config/config.exs` — MODIFIED: add Safety to `:extensions` list
- `familiar/config/test.exs` — MODIFIED: override `:extensions` to `[]` in test env
