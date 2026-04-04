# Story 5.9: File Transaction Module

Status: done

## Story

As a developer building the harness,
I want crash-safe file writes with rollback capability,
So that agent file operations are atomic and parallel agents don't corrupt each other's work.

## Acceptance Criteria

### AC1: Ecto Schema — `file_transactions` Table

**Given** the module needs crash-safe persistence
**When** the migration runs
**Then** a `file_transactions` table exists with columns: `id`, `task_id` (string, indexed), `file_path` (string), `content_hash` (string), `original_content_hash` (string, nullable — nil for new files), `status` (string: `"pending"`, `"completed"`, `"rolled_back"`, `"skipped"`, `"conflict"`), `inserted_at`, `updated_at`
**And** there is a unique index on `[task_id, file_path]`

### AC2: Write Transaction — Strict Sequence

**Given** an agent calls `write_file` during task execution
**When** the transaction module handles the write
**Then** it follows the strict sequence:
  1. Log write intent to SQLite (`status: "pending"`, file path, content hash, task ID)
  2. Stat the file immediately before writing — if modified since task start, save as `.fam-pending` and set `status: "conflict"` (AC6)
  3. Write file to disk via FileSystem behaviour port
  4. Log completion to SQLite (`status: "completed"`)
**And** crash between step 1-2: rollback finds intent without file change, nothing to clean
**And** crash between step 2-3: rollback finds intent without completion, deletes written file / restores original
**And** crash between step 3-4: same as 2-3 — file written but not marked complete

### AC3: Delete Transaction — Logged with Original Content

**Given** an agent calls `delete_file` during task execution
**When** the transaction module handles the delete
**Then** it reads and stores the original file content hash before deleting
**And** logs intent with `original_content_hash` for rollback
**And** follows the same strict sequence as AC2 (log → stat check → delete → log completion)

### AC4: Rollback — Idempotent, Per-File Status

**Given** a task fails, is cancelled, or a crash is detected
**When** `rollback_task/1` is called with the task ID
**Then** it finds all `file_transactions` with `status: "pending"` for that task
**And** for each pending transaction:
  - If the file exists and its hash matches the written content → delete it (undo write) or restore original
  - If the file doesn't exist → mark as `"rolled_back"` (nothing to clean)
  - If the file was modified after the transaction → mark as `"skipped"` (user changed it)
**And** each file's rollback status is updated independently (`"rolled_back"` or `"skipped"`)
**And** re-running rollback on an already-rolled-back task is a no-op (idempotent)

### AC5: File Claim Registration

**Given** agents are executing tasks with file operations
**When** `claimed_files/0` is called
**Then** it returns a map of `%{file_path => task_id}` for all active (non-completed, non-rolled-back) transactions
**And** this enables conflict detection between parallel agents

### AC6: Conflict Detection — `.fam-pending`

**Given** an agent writes to a file that was modified by the user since task start
**When** the pre-write stat check detects the modification (content hash differs from original)
**Then** the agent's version is saved as `<path>.fam-pending`
**And** the transaction status is set to `"conflict"`
**And** the original file is NOT overwritten
**And** `pending_conflicts/0` returns a list of conflict records

### AC7: Recovery Integration

**Given** the daemon crashed with incomplete transactions
**When** `Recovery.rollback_incomplete_transactions/0` runs on startup
**Then** it delegates to the transaction module's `rollback_incomplete/0`
**And** all transactions with `status: "pending"` across ALL tasks are rolled back
**And** the existing stub in `Familiar.Daemon.Recovery` is replaced with the real call

### AC8: Tool Integration — Transparent Wrapping

**Given** `write_file` and `delete_file` tools exist in `Familiar.Execution.Tools`
**When** a task context includes a `task_id`
**Then** file operations are routed through the transaction module
**And** when no `task_id` is present (e.g., system operations), writes go directly to FileSystem (no transaction)
**And** the tool API (`fn(args, context) -> {:ok, result} | {:error, reason}`) is unchanged

### AC9: Content Hashing

**Given** the module needs to detect file modifications
**When** computing a content hash
**Then** it uses `:crypto.hash(:sha256, content) |> Base.encode16(case: :lower)`
**And** the hash is stored in the transaction record for later comparison

### AC10: Test Coverage

**Given** the module is implemented
**When** `mix test` runs
**Then** each function has tests for success and error cases
**And** tests use Mox for FileSystem behaviour port
**And** tests use Ecto sandbox for database operations (real SQLite)
**And** StreamData property tests verify: "Rollback after any crash point leaves filesystem in a consistent state"
**And** Credo strict passes with 0 issues
**And** no regressions on existing test suite

## Tasks / Subtasks

- [x] Task 1: Create Ecto migration for `file_transactions` table (AC: 1)
  - [x] Migration with columns: id, task_id, file_path, content_hash, original_content_hash, status, timestamps
  - [x] Unique index on `[task_id, file_path]`
  - [x] Index on `task_id` for rollback queries
  - [x] Index on `status` for recovery queries

- [x] Task 2: Create `Familiar.Files.Transaction` Ecto schema (AC: 1, 9)
  - [x] Schema matching migration columns
  - [x] Changeset with validations (required: task_id, file_path, content_hash, status)
  - [x] Status enum validation: `~w(pending completed rolled_back skipped conflict)`
  - [x] `content_hash/1` helper: `:crypto.hash(:sha256, content) |> Base.encode16(case: :lower)`
  - [x] `unique_constraint` on `[task_id, file_path]`

- [x] Task 3: Create `Familiar.Files` context module — public API (AC: 2, 3, 5, 6)
  - [x] `write/3` — `(path, content, task_id)` → strict write sequence
  - [x] `delete/2` — `(path, task_id)` → strict delete sequence with original content preservation
  - [x] `claimed_files/0` → map of active file claims
  - [x] `pending_conflicts/0` → list of conflict records
  - [x] `rollback_task/1` → idempotent per-task rollback (AC: 4)
  - [x] `rollback_incomplete/0` → rollback all pending across all tasks (AC: 7)
  - [x] All file I/O through `FileSystem` behaviour port
  - [x] All DB ops through `Familiar.Repo`

- [x] Task 4: Implement conflict detection (AC: 6, 9)
  - [x] Pre-write stat: `file_system().read(path)` → hash → compare to stored original
  - [x] On conflict: write `<path>.fam-pending`, update status to `"conflict"`
  - [x] Store `original_content_hash` at task start or first access

- [x] Task 5: Integrate with `Familiar.Execution.Tools` (AC: 8)
  - [x] `write_file/2` routes through `Files.write/3` when `context.task_id` exists
  - [x] `delete_file/2` routes through `Files.delete/2` when `context.task_id` exists
  - [x] Direct FileSystem delegation when no `task_id` (backward compatible)

- [x] Task 6: Wire recovery stub (AC: 7)
  - [x] Replace `Recovery.rollback_incomplete_transactions/0` stub with `Files.rollback_incomplete/0`

- [x] Task 7: Unit tests (AC: 10)
  - [x] Transaction schema changeset tests
  - [x] `Files.write/3` — golden path, crash simulation (pending without completion)
  - [x] `Files.delete/2` — golden path, rollback restores
  - [x] `Files.rollback_task/1` — pending → rolled_back, already completed → no-op, idempotent re-run
  - [x] `Files.rollback_incomplete/0` — rolls back all pending across tasks
  - [x] `Files.claimed_files/0` — returns active claims
  - [x] `Files.pending_conflicts/0` — returns conflict records
  - [x] Conflict detection: file changed → `.fam-pending` created, status → `"conflict"`
  - [x] Tool integration: `write_file` with/without task_id

- [x] Task 8: StreamData property tests (AC: 10)
  - [x] Property: rollback after write leaves no pending transactions
  - [x] Property: rollback of pending writes marks all as rolled_back or skipped
  - [x] Property: content_hash is deterministic and collision-resistant

- [x] Task 9: Credo, formatting, full regression (AC: 10)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (937 tests + 8 properties)

### Review Findings

- [x] [Review][Decision] Rollback cannot restore original content for overwrites or deletes — resolved by using `git checkout HEAD -- <path>` for tracked files, `skipped` for untracked
- [x] [Review][Patch] `handle_conflict/3` ignores `.fam-pending` write error — added Logger.warning on failure
- [x] [Review][Patch] `update_status/2` uses `Repo.update!` (bang) — changed to `Repo.update` with Logger.warning on error
- [x] [Review][Patch] `mark_completed/1` leaks Ecto changeset on DB error — wrapped in `{:error, {:completion_failed, errors}}`
- [x] [Review][Patch] `"DELETE"` sentinel is a magic string repeated in two locations — extracted to `@delete_sentinel` module attribute
- [x] [Review][Patch] `rollback_task/1` only rolls back `"pending"` — now includes `"conflict"` records via `rollbackable_txns/1`
- [x] [Review][Patch] `rollback_write/1` treats any read error as "file doesn't exist" — now distinguishes `:enoent` (rolled_back) from other errors (skipped with warning)
- [x] [Review][Patch] No integration test for Recovery → Files.rollback_incomplete path — added `continues past individual rollback failures` test
- [x] [Review][Patch] StreamData property tests only cover "file doesn't exist" — added `file_exists` boolean generator covering hash-match rollback path
- [x] [Review][Defer] TOCTOU race between parallel agents — two agents can capture same original_hash and both write without conflict detection. Needs file-level claim checking, belongs in Epic 5.5 (async tool dispatch)
- [x] [Review][Defer] `search_entry/2` in tools.ex recurses on unreadable files with no depth limit — pre-existing from Story 5.8.5
- [x] [Review][Defer] `LocalFileSystem.write/2` `mkdir_p!` raises instead of returning error tuple — pre-existing

## Dev Notes

### Architecture Constraints

- **Module, not a process** — `Familiar.Files` is a context module (like `Familiar.Knowledge`), not a GenServer. SQLite WAL provides crash safety. No process state to lose. [Source: architecture.md line 70]
- **Behaviour ports, not direct calls** — All file I/O through `Familiar.System.FileSystem`, resolved via `Application.get_env(:familiar, Familiar.System.FileSystem)`. [Source: architecture.md, system/file_system.ex]
- **Context boundary** — `Familiar.Files` is its own context. It depends on `System.FileSystem` and `System.Clock`. It is consumed by `Familiar.Execution`. [Source: architecture.md line 908]
- **Strict write sequence is the core invariant** — log intent → stat check → write → log completion. This is the crash safety mechanism. [Source: architecture.md lines 224-228]
- **100% code coverage enforced** — `Files.TransactionLog` (now `Familiar.Files`) is listed as a critical module requiring 100% coverage. [Source: architecture.md line 538]
- **StreamData property test required** — "Rollback after any crash point leaves filesystem in a consistent state" [Source: architecture.md line 553]

### Recovery Integration

The `Familiar.Daemon.Recovery` module (line 114) has a stub for `rollback_incomplete_transactions/0`. Replace it with a call to `Files.rollback_incomplete/0`. Recovery runs synchronously during `Application.start/2` via `RecoveryGate`, before the supervision tree starts — so the `Repo` is available but no agents are running.

### FileSystem Behaviour Signatures

```elixir
# Already defined in system/file_system.ex:
read(path) :: {:ok, binary()} | {:error, {atom(), map()}}
write(path, content) :: :ok | {:error, {atom(), map()}}
stat(path) :: {:ok, %{mtime: DateTime.t(), size: non_neg_integer()}} | {:error, {atom(), map()}}
delete(path) :: :ok | {:error, {atom(), map()}}
ls(path) :: {:ok, [String.t()]} | {:error, {atom(), map()}}
```

Note: `stat/1` already exists in the behaviour — use it for pre-write modification detection. Content hashing via `read/1` is more reliable than mtime for detecting changes.

### Content Hashing Strategy

```elixir
defp content_hash(content) when is_binary(content) do
  :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
end
```

For pre-write stat check: read file → hash content → compare to `original_content_hash` stored at intent time. If different, the user (or another agent) modified the file.

### Tool Integration Pattern

Current `write_file/2` in `tools.ex` delegates directly to `file_system().write(path, content)`. With transaction support:

```elixir
def write_file(args, context) do
  with {:ok, path} <- require_arg(args, :path) do
    content = get_arg(args, :content) || ""
    task_id = Map.get(context, :task_id)

    if task_id do
      # Route through transaction module
      case Files.write(path, content, task_id) do
        {:ok, _transaction} -> {:ok, %{path: path}}
        {:error, {:conflict, _}} -> {:ok, %{path: "#{path}.fam-pending", conflict: true}}
        {:error, _} = error -> error
      end
    else
      # Direct write (no transaction context)
      case file_system().write(path, content) do
        :ok -> {:ok, %{path: path}}
        {:error, _} = error -> error
      end
    end
  end
end
```

### Database Patterns

Follow existing Ecto patterns in the codebase:
- Migration in `familiar/priv/repo/migrations/TIMESTAMP_create_file_transactions.exs`
- Schema in `familiar/lib/familiar/files/transaction.ex`
- Context in `familiar/lib/familiar/files/files.ex`
- Use `Familiar.Repo` for all DB operations
- Tests use `Ecto.Adapters.SQL.Sandbox` (already configured in test.exs)

### Existing Migrations Reference

```
20260401194757_create_vec_test_table.exs
20260401200000_create_knowledge_entries.exs
20260402120000_add_checked_at_to_knowledge_entries.exs
20260403200000_create_conversations.exs
```

Use timestamp `20260404200000` for the new migration (matching 2026-04-04 pattern).

### Previous Story Intelligence (Story 5.8.5)

- `require_arg/2` pattern for nil arg validation — reuse in any new tool functions
- `get_arg/2` supports atom and string keys — `Map.get(args, key, Map.get(args, to_string(key)))`
- `file_system()` helper resolves behaviour port via `Application.get_env`
- Tool functions: `fn(args, context) -> {:ok, result} | {:error, reason}`
- Context map includes `agent_id`, `role`, `conversation_id` — will need `task_id` added
- Test baseline: 905 tests + 5 properties, 0 failures, Credo strict 0 issues

### Project Structure Notes

New files:
```
lib/familiar/files/
├── files.ex             # NEW — Public API context module
├── transaction.ex       # NEW — Ecto schema for file_transactions table

priv/repo/migrations/
├── 20260404200000_create_file_transactions.exs  # NEW

test/familiar/files/
├── files_test.exs       # NEW — Unit + property tests
```

Modified files:
```
lib/familiar/execution/tools.ex          # MODIFIED — route writes/deletes through Files when task_id present
lib/familiar/daemon/recovery.ex          # MODIFIED — replace stub with Files.rollback_incomplete/0
```

### References

- [Source: architecture.md lines 224-228 — file transaction strict write sequence]
- [Source: architecture.md line 70 — file manager is a module, not a process]
- [Source: architecture.md lines 793-796 — files/ directory structure]
- [Source: architecture.md line 908 — Files context boundary]
- [Source: architecture.md line 538 — 100% coverage critical module]
- [Source: architecture.md line 553 — StreamData property: rollback consistency]
- [Source: epics.md lines 1322-1328 — Story 5.9 scope]
- [Source: system/file_system.ex — FileSystem behaviour with stat/1]
- [Source: daemon/recovery.ex line 114 — rollback stub to replace]
- [Source: execution/tools.ex — current write_file/delete_file implementations]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- `Familiar.Files` context module with strict write sequence: log intent → stat check → write → log completion
- `Familiar.Files.Transaction` Ecto schema with SHA-256 content hashing and unique constraint on [task_id, file_path]
- Idempotent rollback: per-file status tracking (pending → rolled_back/skipped), handles writes and deletes
- Conflict detection: pre-write stat check compares content hash, saves `.fam-pending` on mismatch
- Tool integration: `write_file`/`delete_file` route through transaction module when `context.task_id` present, direct FileSystem otherwise
- Recovery wired: `Recovery.rollback_incomplete_transactions/0` stub replaced with `Files.rollback_incomplete/0`
- 39 unit tests + 3 StreamData property tests; 944 total tests + 8 properties, 0 failures
- Credo strict: 0 issues
- Review: git-based rollback for tracked files, `safe_rollback_one` wraps exceptions, `@delete_sentinel` extracted, conflict records included in rollback, transient I/O errors distinguished from enoent

### File List

- `familiar/priv/repo/migrations/20260404200000_create_file_transactions.exs` — NEW: Migration for file_transactions table
- `familiar/lib/familiar/files/transaction.ex` — NEW: Ecto schema with changeset, content_hash/1 helper
- `familiar/lib/familiar/files/files.ex` — MODIFIED: Real implementation replacing stubs (write/3, delete/2, rollback_task/1, rollback_incomplete/0, claimed_files/0, pending_conflicts/0)
- `familiar/lib/familiar/execution/tools.ex` — MODIFIED: write_file/delete_file route through Files when task_id present
- `familiar/lib/familiar/daemon/recovery.ex` — MODIFIED: Stub replaced with Files.rollback_incomplete/0 call
- `familiar/test/familiar/files/files_test.exs` — NEW: 32 unit tests + 3 property tests
