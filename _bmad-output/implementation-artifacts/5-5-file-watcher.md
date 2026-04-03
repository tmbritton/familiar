# Story 5.5: File Watcher

Status: done

## Story

As a developer building the harness,
I want a core GenServer that watches the project directory for changes and broadcasts events,
So that extensions can react to file modifications in real time.

## Acceptance Criteria

### AC1: GenServer Setup with `file_system` Dependency

**Given** the `file_system` hex package is available (transitive via `credo`/`phoenix_live_reload`)
**When** `Familiar.Execution.FileWatcher` is implemented as a GenServer
**Then** `file_system` is added as a direct dependency in `mix.exs`
**And** the watcher starts a `FileSystem` backend process and subscribes to its events
**And** it watches the project directory passed via `:project_dir` option
**And** it is a core process in the supervision tree (not an extension)

### AC2: Event Broadcasting via Hooks

**Given** the watcher detects a file system event
**When** the event is a file creation, modification, or deletion
**Then** it broadcasts a single `:on_file_changed` hook via `Familiar.Hooks.event/2`
**And** the event payload includes `%{path: String.t(), type: :changed | :created | :deleted}` to discriminate event kinds
**And** the broadcast is fire-and-forget (never blocks the watcher)
**And** this matches the architecture's single `on_file_changed` hook declaration

### AC3: Debouncing Rapid Changes

**Given** a file is modified multiple times within a short period (e.g., editor save, formatter, linter)
**When** multiple events arrive for the same file path within 500ms
**Then** only one event is broadcast (the last one after 500ms of quiet)
**And** the debounce window is per-file (concurrent changes to different files are independent)
**And** the default settle time is 500ms, configurable via `:debounce_ms` option

### AC4: Configurable Ignore List

**Given** the watcher is running
**When** events arrive for paths matching the ignore list
**Then** they are silently dropped (no broadcast, no debounce timer)
**And** the default ignore list is: `.git/`, `_build/`, `deps/`, `node_modules/`, `.familiar/`
**And** the ignore list is configurable via `:ignore_patterns` option (list of string prefixes)
**And** paths are compared after normalization (no trailing slashes affecting matching)

### AC5: Supervision Tree Integration

**Given** the application starts
**When** `Familiar.Execution.FileWatcher` is in the supervision tree
**Then** it starts after `Phoenix.PubSub` and `Familiar.Hooks` (depends on both)
**And** it is supervised with `:permanent` restart strategy
**And** it requires a `:project_dir` option (uses `File.cwd!/0` fallback if not provided)
**And** it is conditionally started (disabled in test env via `:start_file_watcher` app env, default `true`)

### AC6: Graceful Start/Stop

**Given** the watcher GenServer
**When** it initializes
**Then** it logs the watched directory and ignore patterns at `Logger.info` level
**And** it handles the `:file_system` backend process lifecycle (starts on init, stops on terminate)
**And** if the project directory does not exist, it returns `{:stop, {:invalid_dir, path}}`

### AC7: Test Coverage

**Given** `Familiar.Execution.FileWatcher` is implemented
**When** `mix test` runs
**Then** tests cover: init with valid/invalid dir, event broadcasting, debounce behavior, ignore list filtering
**And** tests use a real temp directory with `File.write!/2` to trigger events (integration-style)
**And** tests verify debounce by sending rapid events and asserting single broadcast
**And** tests verify ignore patterns suppress events
**And** Credo strict passes with 0 issues
**And** no regressions in existing test suite (774 tests + 5 properties baseline)

## Tasks / Subtasks

- [x] Task 1: Add `file_system` direct dependency (AC: 1)
  - [x] Add `{:file_system, "~> 1.0"}` to `mix.exs` deps
  - [x] Run `mix deps.get` to verify resolution

- [x] Task 2: Create `Familiar.Execution.FileWatcher` GenServer (AC: 1, 6)
  - [x] Create `lib/familiar/execution/file_watcher.ex`
  - [x] `start_link/1` with opts: `:project_dir`, `:debounce_ms`, `:ignore_patterns`
  - [x] `init/1` — validate project_dir exists, start `FileSystem` backend, subscribe
  - [x] `terminate/2` — stop the `FileSystem` backend process
  - [x] State: `%{project_dir, backend_pid, debounce_ms, ignore_patterns, pending: %{}}`
  - [x] Log watched dir and ignore patterns on init

- [x] Task 3: Event classification and broadcasting (AC: 2)
  - [x] `handle_info/2` for `{:file_event, pid, {path, events}}` messages from `file_system`
  - [x] Classify event type from `file_system` flags: `:created`, `:modified`/`:closed` → `:changed`, `:removed` → `:deleted`
  - [x] Broadcast via `Familiar.Hooks.event(:on_file_changed, payload)` with type discriminator in payload
  - [x] Handle `{:file_event, pid, :stop}` — log warning, stop process (supervisor restarts)

- [x] Task 4: Debounce logic (AC: 3)
  - [x] On event arrival: cancel any existing timer for that path, start new `Process.send_after/3` with debounce_ms
  - [x] Store pending timers in state: `%{path => {timer_ref, event_type}}`
  - [x] On timer fire: remove from pending, broadcast the event
  - [x] Default debounce: 500ms
  - [x] Event type merging: `:created` + `:changed` → `:created`; `:deleted` takes priority

- [x] Task 5: Ignore list filtering (AC: 4)
  - [x] Before debounce, check if path matches any ignore pattern
  - [x] Default patterns: `[".git/", "_build/", "deps/", "node_modules/", ".familiar/"]`
  - [x] Match by checking if the relative path (to project_dir) starts with any pattern
  - [x] Normalize: strip trailing `/` from path components before comparison

- [x] Task 6: Supervision tree integration (AC: 5)
  - [x] Add `FileWatcher` to `Familiar.Application` children list after `Familiar.Hooks`
  - [x] Conditional start: `if Application.get_env(:familiar, :start_file_watcher, true)`
  - [x] Pass `project_dir: File.cwd!()` as default
  - [x] Disabled in test env via `config/test.exs`

- [x] Task 7: Update Boundary exports (AC: 1)
  - [x] Add `Familiar.Execution.FileWatcher` to `Familiar.Execution` boundary exports

- [x] Task 8: Tests (AC: 7)
  - [x] Create `test/familiar/execution/file_watcher_test.exs`
  - [x] Test: init with valid temp dir succeeds
  - [x] Test: init with nonexistent dir returns error
  - [x] Test: file creation broadcasts with type: :created
  - [x] Test: file modification broadcasts with type: :changed
  - [x] Test: file deletion broadcasts with type: :deleted
  - [x] Test: rapid changes to same file debounced to single event
  - [x] Test: changes to different files are independent (no cross-debounce)
  - [x] Test: ignored paths do not trigger events
  - [x] Test: custom ignore patterns work
  - [x] Test: custom debounce_ms respected

- [x] Task 9: Credo, formatting, full regression (AC: 7)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (784 tests + 5 properties)

### Review Findings

- [x] [Review][Decision] Delete events fire immediately (no debounce) — eliminates `:deleted` + `:created` merge ambiguity; only `:created`/`:changed` are debounced
- [x] [Review][Decision] Debounce timer race — fixed: `ref` included in `{:debounce_fire, ref, path}` message; handler verifies ref matches current pending entry
- [x] [Review][Patch] `File.cwd!()` removed from `application.ex` — supervisor passes no opts; `init/1` resolves via `Keyword.get_lazy` at init time
- [x] [Review][Patch] `ignored?/2` rewritten to split path into components and match directory names exactly — no more `.git_backup` false positives
- [x] [Review][Patch] Added 4 tests: 500ms default debounce, denormalized ignore pattern, `.git_backup` false-positive regression, deletion-fires-immediately
- [x] [Review][Defer] Backend process leak on abnormal kill (`:kill` signal) — `terminate/2` not called, `FileSystem` backend orphaned. Inherent OTP limitation; would need supervisor-based backend management — deferred to harness hardening story
- [x] [Review][Defer] Project dir deleted while running causes supervisor restart loop — needs backoff/circuit-breaker in watcher or supervisor strategy change — deferred to resilience story
- [x] [Review][Defer] Symlinks outside project_dir bypass ignore rules — `Path.relative_to/2` returns absolute path unchanged — deferred to security hardening (Story 5.6 Safety Extension may address)

## Dev Notes

### Architecture Constraints

- **Core process, NOT an extension** — FileWatcher is harness infrastructure like AgentProcess and ToolRegistry. It sits in the supervision tree directly, not loaded via ExtensionLoader. [Source: epics.md line 1296, architecture.md line 1824-1833]
- **Broadcasts via Hooks.event/2** — Uses the existing Hooks event dispatch (which already handles PubSub broadcast + crash isolation). The `on_file_changed` hook is already declared in Hooks module. [Source: hooks.ex line 22]
- **`file_system` hex package** — Already in `mix.lock` as transitive dep (via `credo` and `phoenix_live_reload`). Must be added as direct dep since we're using it directly. Version `~> 1.0` (currently 1.1.1 in lock). [Source: mix.lock]
- **Hexagonal architecture** — FileWatcher uses `Familiar.Hooks` for broadcasting (not raw PubSub). This keeps the event flow consistent and lets extensions subscribe through the established hook mechanism.

### `file_system` Package API

The `file_system` package wraps platform-specific watchers (inotify on Linux, FSEvents on macOS):

```elixir
# Start a backend watching a directory
{:ok, pid} = FileSystem.start_link(dirs: ["/path/to/watch"])
FileSystem.subscribe(pid)

# Events arrive as messages:
# {:file_event, pid, {path, events}}  — events is a list of atoms like [:modified, :closed]
# {:file_event, pid, :stop}           — backend stopped
```

Event flags vary by platform. Common flags:
- Linux (inotify): `:created`, `:modified`, `:closed_write`, `:moved_to`, `:moved_from`, `:deleted`, `:isdir`
- macOS (FSEvents): `:created`, `:modified`, `:removed`, `:renamed`, `:inodemetamod`

### Event Classification Strategy

Map platform-specific flags to normalized types:
- `:created` in flags → `:on_file_created`
- `:removed` or `:deleted` in flags → `:on_file_deleted`
- `:modified`, `:closed_write`, `:renamed`, `:moved_to`, or others → `:on_file_changed`

Priority: if both `:created` and `:modified` appear (common on Linux), prefer `:created`.

### Hooks Integration

The `Familiar.Hooks` module already declares `on_file_changed` as an event hook (line 22). The new hooks `on_file_created` and `on_file_deleted` follow the same pattern. Hooks.event/2 is fire-and-forget — it broadcasts to all registered event hook subscribers without blocking.

```elixir
# Example broadcast from FileWatcher:
Familiar.Hooks.event(:on_file_changed, %{path: "/project/lib/foo.ex", type: :changed})
```

### Debounce Implementation

Per-file debounce using `Process.send_after/3`:
- State tracks `pending: %{path => {timer_ref, event_type}}`
- On new event: `Process.cancel_timer(old_ref)`, start new timer
- On timer fire: `handle_info({:debounce_fire, path}, state)` → broadcast + remove from pending

This is a standard GenServer debounce pattern. No external libraries needed.

### Test Strategy

Tests need real filesystem events. Use `System.tmp_dir!/0` to create isolated temp dirs. The `file_system` backend needs ~100ms to initialize, so tests should allow for startup time. Debounce tests can:
1. Subscribe to PubSub/Hooks topic
2. Write files rapidly
3. Assert only one event received after debounce window

Consider marking tests as `@tag :file_watcher` so they can be excluded if platform inotify is unavailable (CI containers).

### Existing Patterns to Follow

- **GenServer with conditional start**: See `Familiar.Daemon.Server` pattern in `application.ex` line 28-30 — uses `if(Application.get_env(...), do: Module)`
- **Activity broadcasting**: See `AgentProcess` — calls `Hooks.event/2` for lifecycle events
- **Boundary exports**: Add to `Familiar.Execution` module's `exports` list

### Previous Story Intelligence (Story 5.4)

- Pure function modules work well — but FileWatcher is a GenServer (stateful debounce + backend process lifecycle)
- Hooks.event/2 is the standard way to broadcast from core processes
- Test baseline: 774 tests + 5 properties, 0 failures
- Credo strict: 0 issues

### Deferred Items (NOT in scope)

- **Config from `.familiar/config.toml`** — The epics mention watcher config from `[watcher]` TOML section. No TOML config system exists yet. Use application env / opts for now. TOML config is a future story.
- **Recursive directory watching** — `file_system` handles recursive watching by default. No special handling needed.
- **Knowledge Store freshness integration** — That's Story 5.7 (Knowledge Store Extension). FileWatcher just broadcasts; KS extension subscribes.

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── file_watcher.ex         # NEW — FileWatcher GenServer

test/familiar/execution/
├── file_watcher_test.exs   # NEW — Integration tests with real filesystem
```

Modified files:
```
mix.exs                              # MODIFIED — add file_system direct dep
lib/familiar/application.ex          # MODIFIED — add FileWatcher to supervision tree
lib/familiar/execution/execution.ex  # MODIFIED — add FileWatcher to boundary exports
```

### References

- [Source: epics.md line 1290-1296 — Story 5.5 scope definition]
- [Source: architecture.md line 65 — Prompt Assembly Pipeline / process architecture]
- [Source: architecture.md line 1792 — on_file_changed hook definition]
- [Source: architecture.md line 1800 — Knowledge Store extension uses on_file_changed]
- [Source: architecture.md line 1824-1833 — Harness core vs extensions distinction]
- [Source: hooks.ex line 22 — on_file_changed already declared]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- FileWatcher GenServer wrapping `file_system` hex package with inotify/FSEvents backend
- Consolidated to single `:on_file_changed` hook with `type: :created | :changed | :deleted` discriminator (matches architecture's hook declaration)
- Per-file debounce via `Process.send_after/3` with configurable settle time (default 500ms)
- Event type merging during debounce: `:created` + `:changed` → `:created`; `:deleted` takes priority
- Configurable ignore list with path prefix matching (default: `.git/`, `_build/`, `deps/`, `node_modules/`, `.familiar/`)
- Supervision tree integration with conditional start (disabled in test env)
- 14 integration tests using real temp dirs and filesystem events; 0 regressions in 788-test suite
- Credo strict: 0 issues
- Review: deletion fires immediately (no debounce), ref-checked debounce timers, component-based ignore matching, `File.cwd!` deferred to init time

### File List

- `familiar/mix.exs` — MODIFIED: add `{:file_system, "~> 1.0"}` direct dependency
- `familiar/lib/familiar/execution/file_watcher.ex` — NEW: FileWatcher GenServer
- `familiar/lib/familiar/application.ex` — MODIFIED: add FileWatcher to supervision tree
- `familiar/lib/familiar/execution/execution.ex` — MODIFIED: add FileWatcher to boundary exports
- `familiar/config/test.exs` — MODIFIED: disable file watcher in test env
- `familiar/test/familiar/execution/file_watcher_test.exs` — NEW: 10 integration tests
