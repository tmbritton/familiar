# Story 1.3a: Daemon Lifecycle

Status: done

## Story

As a user,
I want the Familiar daemon to run as a background process with health monitoring and crash recovery,
so that the system is always available and recovers gracefully from failures.

## Acceptance Criteria

1. **Daemon Startup:** When the daemon starts, a Phoenix application runs as a background process. A dynamic port is written to `.familiar/daemon.json`. A PID file is written to `.familiar/daemon.pid` with advisory lock.
2. **Health Endpoint:** `GET /api/health` responds with `{"status": "ok", "version": "x.y.z"}`.
3. **Graceful Shutdown:** When `fam daemon stop` is issued (or the daemon receives a shutdown signal), it shuts down gracefully, writes a clean shutdown marker, and cleans up `.familiar/daemon.json`.
4. **Crash Recovery:** When the daemon restarts after an unclean shutdown (no clean shutdown marker), crash recovery runs: database integrity check → file transaction rollback → orphaned task reconciliation. Each phase is a hook that later stories fill with real logic.
5. **PID File Lock:** Advisory file lock on `.familiar/daemon.pid` prevents two daemons from racing to start simultaneously.
6. **Testing:** Health endpoint, PID file management, shutdown marker, and crash recovery sequence are tested. Near-100% coverage on daemon lifecycle modules.

## Tasks / Subtasks

- [x] Task 1: Create `.familiar/` directory management module (AC: #1)
  - [x] `Familiar.Daemon.Paths` with project_dir/0, familiar_dir/0, daemon_json_path/0, daemon_pid_path/0, daemon_lock_path/0, shutdown_marker_path/0, db_path/0, ensure_familiar_dir!/0
  - [x] project_dir configurable via `:project_dir` app env (defaults to File.cwd!)
- [x] Task 2: Create PID file management (AC: #1, #5)
  - [x] `Familiar.Daemon.PidFile` with write/0, read/0, cleanup/0, alive?/0
  - [x] Uses `:os.getpid()` for OS PID, checks existing PID liveness via `kill -0`
  - [x] Returns `{:error, {:daemon_already_running, %{pid: pid}}}` if process alive
- [x] Task 3: Create daemon.json management (AC: #1)
  - [x] `Familiar.Daemon.StateFile` with write/1, read/0, cleanup/0
  - [x] Pretty-printed JSON with port, pid, started_at fields
- [x] Task 4: Create shutdown marker management (AC: #3, #4)
  - [x] `Familiar.Daemon.ShutdownMarker` with write/0, exists?/0, clear/0, unclean_shutdown?/0
  - [x] Unclean detection: .familiar/ exists AND marker does NOT
- [x] Task 5: Create crash recovery gate (AC: #4)
  - [x] `Familiar.Daemon.Recovery` with run_if_needed/0, run/0, check_database_integrity/0, rollback_incomplete_transactions/0, reconcile_orphaned_tasks/0
  - [x] DB integrity: runs PRAGMA integrity_check, rescues if Repo unavailable
  - [x] Transaction rollback + task reconciliation: stubs returning :ok
  - [x] Each phase logged, failures don't block subsequent phases
- [x] Task 6: Add health API endpoint (AC: #2)
  - [x] `FamiliarWeb.HealthController` — `GET /api/health` → `{status: "ok", version: vsn}`
  - [x] API scope added to router with `:api` pipeline
- [x] Task 7: Create daemon lifecycle GenServer (AC: #1, #3)
  - [x] `Familiar.Daemon.Server` — init writes PID+state+clears marker, terminate writes marker+cleans up
  - [x] handle_call for :status and :stop
  - [x] handle_info for EXIT messages (trap_exit enabled)
  - [x] Recovery gate runs in init (after Repo is available in supervision tree)
- [x] Task 8: Wire into Application supervision tree (AC: #1, #4)
  - [x] Daemon.Server conditionally started via `:start_daemon` config (disabled in test)
  - [x] Server positioned after Repo, before Endpoint
  - [x] Uses configured port from Endpoint config
- [x] Task 9: Write unit tests for daemon lifecycle (AC: #6)
  - [x] paths_test.exs: 7 tests — path construction + ensure_familiar_dir!
  - [x] pid_file_test.exs: 7 tests — write/read/cleanup/alive + stale PID handling
  - [x] state_file_test.exs: 5 tests — write/read/cleanup + invalid JSON
  - [x] shutdown_marker_test.exs: 6 tests — write/exists/clear + unclean detection
  - [x] recovery_test.exs: 6 tests — recovery gate + individual phases
  - [x] health_controller_test.exs: 3 tests — JSON response, status, content type
  - [x] server_test.exs: 5 tests — start/status/stop/terminate lifecycle
  - [x] All file tests use @moduletag :tmp_dir for isolation
- [x] Task 10: Final verification (AC: all)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix test` — 117 tests + 4 properties, 0 failures (9 integration excluded)
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — no issues
  - [x] Boundary checks pass

### Review Findings

- [x] [Review][Decision] D1: Recovery gate placement — Fixed: created RecoveryGate module using `:ignore` pattern. Placed in supervision tree after Repo/Migrator, runs synchronously before other children. Decoupled from Daemon.Server.
- [x] [Review][Patch] P1: Lock file — Fixed: `acquire_lock/0` uses `File.open([:write, :exclusive])` for atomic lock. Stale lock detection + cleanup on retry.
- [x] [Review][Patch] P2: daemon_already_running test — Fixed: added test that writes current PID then asserts second write returns error.
- [x] [Review][Patch] P3: Recovery marker clearing — Fixed: `run/0` returns `:ok | :error`. Marker only cleared on `:ok`. Failed recovery preserves marker for next restart.
- [x] [Review][Patch] P4: Server.init catch-all — Fixed: added `{:error, {type, details}}` clause that returns `{:stop, {type, details}}`.
- [x] [Review][Patch] P5: PID validation — Fixed: `valid_pid_string?/1` validates positive integer before `kill -0`. `read/0` returns `{:error, {:invalid_config, ...}}` for malformed PIDs.
- [x] [Review][Patch] P6: terminate ordering — Fixed: cleanup StateFile + PidFile first, write ShutdownMarker last.
- [x] [Review][Patch] P7: StateFile validation — Fixed: pattern match on `%{port: _, pid: _, started_at: _}` in `write/1`.
- [x] [Review][Patch] P8: @impl consistency — Fixed: removed redundant `@impl true` on second handle_info clause.
- [x] [Review][Patch] P9: Process.sleep — Fixed: uses `Process.monitor` + `assert_receive {:DOWN, ...}` instead.
- [x] [Review][Defer] W1: Server.init performs blocking I/O — should use {:continue, :post_init}. Deferred: fast for MVP.
- [x] [Review][Defer] W2: HealthController doesn't check actual daemon/DB liveness. Deferred: deep health is future scope.

## Dev Notes

### Architecture Compliance

**Source:** [architecture.md — Daemon Lifecycle, Core Processes, Crash Recovery]

**Daemon as Phoenix Application:** The daemon IS the Phoenix application running as a background process. Each project gets its own BEAM instance on a dynamic port. The CLI (Story 1.3b) is a thin HTTP client.

**Crash Recovery Gate:** Runs as a **synchronous function call in `Application.start/2`** — BEFORE the supervision tree starts. Not a process, but a startup gate. This ensures the system is in a known-good state before any processes begin.

**Three Recovery Phases:**
1. **Database integrity check:** `PRAGMA integrity_check` on SQLite. Full backup/restore comes in Story 2.5.
2. **File transaction rollback:** Stub for now. Real implementation in Story 5.2 (File Transaction Module).
3. **Orphaned task reconciliation:** Stub for now. Real implementation in Story 4.1a (Task State Machine).

**IMPORTANT:** The recovery phases are STUBS in this story. They log and return `:ok`. The framework/mechanism is what matters — later stories fill in the logic.

**Clean Shutdown Marker Pattern:**
- On clean shutdown: write `.familiar/shutdown_marker`
- On startup: check if `.familiar/` exists BUT marker does NOT → unclean shutdown detected → run recovery
- If `.familiar/` doesn't exist → fresh install, no recovery needed
- If marker exists → clean shutdown, clear marker and proceed normally

### Supervision Tree After This Story

```
Familiar.Application (one_for_one)
├── FamiliarWeb.Telemetry
├── Familiar.Repo
├── Ecto.Migrator
├── DNSCluster
├── Phoenix.PubSub
├── Familiar.Daemon.Server      # NEW — daemon lifecycle GenServer
└── FamiliarWeb.Endpoint
```

**Startup sequence:**
1. `Application.start/2` calls `Recovery.run_if_needed/0` (synchronous gate)
2. Supervision tree starts in order
3. `Daemon.Server.init/1` writes PID file + daemon.json + clears marker
4. Endpoint starts and binds to port
5. Daemon.Server may need to update daemon.json with actual port after Endpoint is ready

### Port Discovery

The Endpoint binds to port 0 (dynamic) in daemon mode. The actual port is available via `FamiliarWeb.Endpoint.config(:http)` or `FamiliarWeb.Endpoint.url()` AFTER the Endpoint starts. Since Daemon.Server starts before Endpoint in the supervision tree, it may need to:
- Write daemon.json with a placeholder port initially
- Update it once Endpoint reports its bound port (via a delayed check or PubSub notification)

**Simpler approach:** Have Daemon.Server start AFTER Endpoint, or use `Endpoint.server?/0` to check if the server is running, then read the port. Alternatively, configure a fixed port in dev (4000) and only use dynamic ports in production/daemon mode.

**Recommended approach for MVP:** Use a configured port (from config). The CLI reads daemon.json to discover it. Dynamic port allocation is a production concern — for now, use the configured port from `config/dev.exs` (4000) or `config/runtime.exs`.

### PID File Advisory Lock

Elixir/Erlang don't have native flock. Options:
1. **File.open with exclusive mode:** `File.open(path, [:write, :exclusive])` fails if file exists. Combined with checking if the PID in the file is still alive.
2. **Lock file pattern:** Create `.familiar/daemon.lock` exclusively. If creation fails → another daemon is starting. Check if the PID in daemon.pid is still alive; if not, stale lock → remove and retry.
3. **Simple approach:** Write PID file, check if existing PID is alive via `System.cmd("kill", ["-0", pid_string])` or `/proc/PID` check on Linux.

**Recommended for MVP:** Write PID file with OS PID. On startup, if PID file exists, check if that PID is still alive. If alive → error. If dead → stale file, remove and proceed.

### .familiar/ Directory Structure (After This Story)

```
.familiar/
├── daemon.json          # Runtime: {port, pid, started_at}
├── daemon.pid           # Runtime: OS process ID
├── shutdown_marker      # Clean shutdown indicator (empty file)
├── familiar.db          # SQLite database (existing from Story 1.1a)
```

### Error Handling

Daemon lifecycle errors use the established convention:
- `{:error, {:daemon_already_running, %{pid: pid}}}` — another daemon is alive
- `{:error, {:storage_failed, %{reason: ...}}}` — database integrity check failed (from Story 1.2's error types)
- `{:error, {:invalid_config, %{field: ..., reason: ...}}}` — daemon config invalid

### Boundary Configuration

All new modules go under `Familiar.Daemon` namespace. This is NOT a separate boundary context — it's part of the core application infrastructure. No new `use Boundary` needed; these modules are internal to the application.

### Testing Strategy

**File-based tests:** Use `System.tmp_dir!/0` or `@tag :tmp_dir` to create isolated temp directories. Set `Familiar.Daemon.Paths` project_dir to the temp dir via application config or function parameter.

**Health endpoint test:** Use `ConnCase` to test the JSON API response.

**GenServer tests:** Start the GenServer in the test with a temp directory. Verify files are written on init and cleaned up on terminate.

**Recovery tests:** Mock the file system state (create/remove shutdown marker) and verify the recovery gate runs/skips correctly.

### Previous Story Learnings (from Stories 1.1a, 1.1b, 1.2)

- sqlite-vec vectors: JSON array strings ONLY, not binary encoding
- `async: false` required for tests touching sqlite-vec virtual tables
- Credo requires alphabetical alias ordering and `strict: true`
- `Mox.verify_on_exit!/1` needs context parameter
- Error convention: `{:error, {atom_type, map_details}}` — never bare atoms
- Boundary exports must explicitly list self
- `Application.get_env` for adapter resolution pattern
- `mix format` auto-fixes — don't fight it
- Compensating deletes on multi-step operations (learned from 1.2 review)

### What NOT to Do in This Story

- **Do NOT implement the CLI entry point** — that's Story 1.3b
- **Do NOT implement auto-start from CLI** — that's Story 1.3b
- **Do NOT implement init mode** — that's Story 1.3b/1.4
- **Do NOT implement real file transaction rollback** — that's Story 5.2 (stub only)
- **Do NOT implement real orphaned task reconciliation** — that's Story 4.1a (stub only)
- **Do NOT implement backup/restore** — that's Story 2.5 (stub integrity check only)
- **Do NOT implement the embedding worker pool** — that's Story 1.4
- **Do NOT implement `fam daemon stop` CLI command** — that's Story 1.3b (just the GenServer stop handler here)
- **Do NOT implement dynamic port allocation** — use configured port for MVP

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Daemon Lifecycle]
- [Source: _bmad-output/planning-artifacts/architecture.md#Core Processes & Supervision Tree]
- [Source: _bmad-output/planning-artifacts/architecture.md#Crash Recovery Gate]
- [Source: _bmad-output/planning-artifacts/architecture.md#Graceful Degradation Modes]
- [Source: _bmad-output/planning-artifacts/architecture.md#CLI Entry Point Flow]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3a]
- [Source: _bmad-output/implementation-artifacts/1-2-provider-adapters-embedding-pipeline.md#Completion Notes]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Recovery gate originally placed in Application.start/2 before supervision tree — Repo not available yet. Moved to Daemon.Server.init/1 (runs after Repo starts).
- `@tag :tmp_dir` before `setup` causes ExUnit warning "unused @tag before describe" — must use `@moduletag :tmp_dir` at module level.
- Daemon.Server registered with `name: __MODULE__` — tests can't start a second one while app server is running. Fixed with `config :familiar, start_daemon: false` in test.exs.
- `Process.flag(:trap_exit, true)` causes noisy EXIT messages from ports — added handle_info clauses.
- `:os.getpid()` returns charlist, not string — pipe through `to_string()`.
- Credo strict requires aliases for nested module references in tests (e.g., `Familiar.Daemon.Paths.ensure_familiar_dir!` → `Paths.ensure_familiar_dir!`).
- Credo strict prefers implicit `try` (rescue at function level) over explicit `try do ... rescue`.

### Completion Notes List

- 6 new daemon modules: Paths, PidFile, StateFile, ShutdownMarker, Recovery, Server
- Health API endpoint at GET /api/health with version from Application.spec
- Crash recovery gate with 3-phase framework (DB integrity real, others stub)
- PID file liveness check via kill -0 to prevent duplicate daemons
- Daemon.Server GenServer manages full lifecycle: init → runtime → shutdown
- Conditionally disabled in test env via :start_daemon config
- All tests use @moduletag :tmp_dir for file system isolation
- 42 new tests (117 total), 0 failures

### File List

- lib/familiar/daemon/paths.ex (new — .familiar/ path resolution)
- lib/familiar/daemon/pid_file.ex (new — PID file management)
- lib/familiar/daemon/state_file.ex (new — daemon.json management)
- lib/familiar/daemon/shutdown_marker.ex (new — clean shutdown marker)
- lib/familiar/daemon/recovery.ex (new — crash recovery gate)
- lib/familiar/daemon/server.ex (new — daemon lifecycle GenServer)
- lib/familiar/application.ex (modified — conditional daemon child)
- lib/familiar/error.ex (modified — added :storage_failed, :query_failed in previous story)
- lib/familiar_web/router.ex (modified — added /api scope with health endpoint)
- lib/familiar_web/controllers/health_controller.ex (new — health check)
- config/test.exs (modified — start_daemon: false)
- test/familiar/daemon/paths_test.exs (new — 7 tests)
- test/familiar/daemon/pid_file_test.exs (new — 7 tests)
- test/familiar/daemon/state_file_test.exs (new — 5 tests)
- test/familiar/daemon/shutdown_marker_test.exs (new — 6 tests)
- test/familiar/daemon/recovery_test.exs (new — 6 tests)
- test/familiar/daemon/server_test.exs (new — 5 tests)
- test/familiar_web/controllers/health_controller_test.exs (new — 3 tests)
