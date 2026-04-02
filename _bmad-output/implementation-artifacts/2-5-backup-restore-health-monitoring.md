# Story 2.5: Backup, Restore & Health Monitoring

Status: done

## Story

As a user,
I want automatic backups, easy restore, and health visibility for the knowledge store,
So that I never lose accumulated knowledge and can quickly assess system state.

## Acceptance Criteria

1. **Given** the user runs `fam backup`, **Then** a snapshot of `familiar.db` is created in `.familiar/backups/` with a timestamp filename (e.g., `familiar-2026-04-02T120000Z.db`), **And** the result shows the backup path and size.

2. **Given** the user runs `fam restore`, **Then** available snapshots are listed with timestamps and sizes, **And** the user selects one to restore, **And** a confirmation prompt is displayed ("Restore from <date> backup? Current database will be replaced. (y/n)") — this is the ONLY command requiring confirmation (UX-DR19), **And** on confirmation the database file is replaced and the daemon restarts.

3. **Given** the user runs `fam restore <timestamp>`, **Then** the specific backup is restored directly (still with confirmation).

4. **Given** the daemon starts and `check_database_integrity/0` fails (already implemented in `Recovery`), **When** a backup exists in `.familiar/backups/`, **Then** the system auto-restores from the most recent backup (FR19c), **And** logs "Database restored from backup (<date>). Verify with `fam status`".

5. **Given** the user runs `fam status` or `fam context --health`, **Then** output shows: entry count, staleness ratio (stale/total), last refresh timestamp, backup status (last backup date, count), **And** health is summarized as green/amber/red signal.

6. **Given** backup/restore/health commands, **Then** all support `--json`, `--quiet`, `--text` output modes per FR78.

7. **Given** unit tests run, **Then** backup creation, restore flow, auto-restore on corruption, health metrics collection, and CLI commands are all tested with near-100% coverage.

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Knowledge.Backup` module (AC: 1, 2, 3)
  - [x] 1.1 `create/1` — copy `familiar.db` to `.familiar/backups/` with timestamp filename
  - [x] 1.2 `list/0` — list backups sorted newest-first with metadata (size, timestamp)
  - [x] 1.3 `restore/2` — replace `familiar.db` from backup file (takes backup path + opts)
  - [x] 1.4 `latest/0` — return path to most recent backup (for auto-restore)
  - [x] 1.5 `prune/1` — delete backups older than retention limit (keep last 10 by default)

- [x] Task 2: Wire auto-restore into `Daemon.Recovery` (AC: 4)
  - [x] 2.1 Update `check_database_integrity/0` to call `Backup.restore(Backup.latest())` on failure
  - [x] 2.2 If no backup exists, log warning and continue (fail-open)
  - [x] 2.3 If restore fails, log error and continue (fail-open, matches existing Recovery pattern)

- [x] Task 3: Implement `Knowledge.health/0` (AC: 5)
  - [x] 3.1 Replace stub in `knowledge.ex:169` with real implementation
  - [x] 3.2 Collect: entry_count, type breakdown, staleness_ratio, last_refresh (max updated_at), backup_status (last backup date, count)
  - [x] 3.3 Compute signal: green (staleness < 10%), amber (10-30%), red (> 30% or no backup)

- [x] Task 4: CLI commands — `backup`, `restore`, `context --health` (AC: 1, 2, 3, 5, 6)
  - [x] 4.1 Add `backup` command to `parse_args/1` and `run_with_daemon/2`
  - [x] 4.2 Add `restore` command — list mode (no args) and direct mode (with timestamp arg)
  - [x] 4.3 Add `context --health` flag to existing `context` command
  - [x] 4.4 Text formatters for backup result, restore list, health report
  - [x] 4.5 Quiet summaries and error messages in `output.ex`
  - [x] 4.6 Update help text

- [x] Task 5: Confirmation prompt for restore (AC: 2)
  - [x] 5.1 Add `confirm_fn` to deps map (defaults to IO.gets-based prompt)
  - [x] 5.2 Restore command calls `confirm_fn` before executing; returns `{:error, {:cancelled, %{}}}` if declined
  - [x] 5.3 `--json` and `--force` modes skip confirmation (machine callers handle confirmation externally)

- [x] Task 6: Comprehensive test coverage (AC: 7)
  - [x] 6.1 Backup module tests: create, list, restore, latest, prune (15 tests)
  - [x] 6.2 Recovery integration: auto-restore wired, integrity check tested (8 tests)
  - [x] 6.3 Health metrics: all signals (green/amber/red), edge cases (empty store, no backups) (5 tests)
  - [x] 6.4 CLI tests: backup, restore (with mock confirm_fn), context --health (9 tests)
  - [x] 6.5 All three output modes supported via existing Output.format/3

## Dev Notes

### Existing Code to Reuse

| What | Where | How |
|------|-------|-----|
| `Knowledge.health/0` stub | `knowledge.ex:167-169` | Replace with real implementation |
| `Recovery.check_database_integrity/0` | `recovery.ex:65-85` | Wire auto-restore on failure (line 67 has `# Full backup/restore comes in Story 2.5`) |
| `Paths.familiar_dir/0` | `paths.ex:15` | Use for backup directory: `Path.join(Paths.familiar_dir(), "backups")` |
| `Paths.db_path/0` | `paths.ex:32` | Source for backup copy |
| CLI command dispatch pattern | `main.ex` | Follow existing `run_with_daemon/2` pattern |
| `Output.format/3` | `output.ex` | JSON/text/quiet formatting |
| DI pattern | `management.ex:299-303` | `Keyword.get_lazy(opts, :key, fn -> default end)` |
| `Entry` schema queries | `management.ex:107-114` | `Repo.all(Entry)`, `from(e in Entry, ...)` |
| `Freshness.validate_entries/2` | `freshness.ex` | For staleness ratio in health metrics |

### Architecture Constraints

- **Backup is a file copy, not a logical export.** Copy `familiar.db` (the SQLite file). SQLite supports safe concurrent reads via WAL mode. Use `File.cp/2` — SQLite's WAL checkpoint ensures consistency.
- **Restore requires daemon restart.** After replacing the DB file, the Ecto connection pool must reconnect. The restore function should signal the daemon to restart (or the CLI can issue `fam daemon restart` after restore).
- **Recovery is a startup gate.** `Recovery.run_if_needed/0` runs in `Application.start/2` before the supervision tree. Auto-restore happens here — no processes are running yet, so DB replacement is safe.
- **No FileSystem behaviour for backups.** Backup operates on `.familiar/` internals (not project files). Use `File` module directly, same as `Paths`, `ShutdownMarker`, `StateFile`. This is consistent with other daemon modules.
- **Health aggregation queries DB directly.** Use `Repo.aggregate(Entry, :count)` and friends. No need for behaviour abstraction — this is internal DB state.

### Confirmation Pattern (UX-DR19)

`fam restore` is the ONLY command requiring confirmation. All other destructive actions (delete, fix, execute) run immediately. Implementation:
- Default `confirm_fn` uses `IO.gets("Restore from <date> backup? Current database will be replaced. (y/n): ")`
- Test mock injects `confirm_fn: fn _prompt -> "y\n" end` in deps map
- `--json` mode: skip confirmation (machine callers confirm externally), or require `--force` flag

### Health Signal Logic

```
green:  staleness_ratio < 0.10 AND has_backup
amber:  staleness_ratio 0.10..0.30 OR no_backup
red:    staleness_ratio > 0.30 OR (no_backup AND entry_count > 0)
```

Return structure:
```elixir
%{
  entry_count: 42,
  types: %{"fact" => 15, "convention" => 10, ...},
  staleness_ratio: 0.05,
  last_refresh: ~U[2026-04-02 10:00:00Z],
  backup: %{last: ~U[2026-04-02 09:00:00Z], count: 3},
  signal: :green
}
```

### File Structure

New files:
```
lib/familiar/knowledge/backup.ex           # Backup/restore operations
test/familiar/knowledge/backup_test.exs    # Backup module tests
```

Modified files:
```
lib/familiar/daemon/recovery.ex            # Wire auto-restore
lib/familiar/knowledge/knowledge.ex        # Implement health/0
lib/familiar/cli/main.ex                   # Add backup/restore/health commands
lib/familiar/cli/output.ex                 # Formatters and error messages
lib/familiar/daemon/paths.ex               # Add backups_dir/0
test/familiar/daemon/recovery_test.exs     # Auto-restore tests
test/familiar/cli/main_test.exs            # CLI command tests
```

### Testing Strategy

- **Backup tests:** Use `tmp_dir` ExUnit tag or create temp directories. Copy a real (test) SQLite DB, verify backup files created with correct naming, list returns sorted, restore replaces file, prune respects retention.
- **Recovery tests:** Mock `Backup` functions (or use DI opts) to test auto-restore path in `check_database_integrity/0`. Test: integrity OK (no restore), integrity fail + backup exists (restore), integrity fail + no backup (warn and continue).
- **Health tests:** Create entries with known freshness states, verify counts and ratios. Test all three signal thresholds.
- **CLI tests:** Follow existing pattern — inject deps map with mock functions. Test `confirm_fn` injection for restore. Test all output modes.
- All tests `async: false` (sqlite-vec virtual table limitation).
- `Mox.set_mox_global()` + `setup :verify_on_exit!` in all test modules.

### Previous Story Intelligence (from 2.4)

- **OptionParser strict mode:** Register ALL new flags (`--health`) in `parse_args/1` strict list. P1 from 2.4 review.
- **CLI test pattern:** Use flags map (`%{health: true}`) not string args for flag-based commands.
- **Credo strict:** Max nesting depth 2. Extract helpers early. Alphabetize aliases.
- **DI for testability:** Pass `opts` keyword through. Use `Keyword.get_lazy` for defaults.
- **embed-before-persist:** Not directly relevant here, but maintain pattern awareness.
- **Error tuples:** Always `{:error, {atom_type, %{details}}}`, never bare atoms.

### Edge Cases

- Backup directory doesn't exist yet → `File.mkdir_p/1` before first backup
- No backups available for restore → `{:error, {:no_backups, %{}}}`
- Backup file corrupted → integrity check on restore? (defer — SQLite's own integrity is sufficient)
- DB locked during backup → WAL mode checkpoint; `File.cp` should succeed for reads
- Restore while daemon running (via CLI) → need daemon restart signal after restore
- Empty knowledge store → health returns `signal: :green` (nothing stale), entry_count: 0

### Project Structure Notes

- `backup.ex` goes in `knowledge/` context (manages knowledge store state) — consistent with `management.ex`, `freshness.ex`
- `Paths.backups_dir/0` added to `paths.ex` for `.familiar/backups/` resolution
- No new behaviour ports needed — backup is internal file operations, not external system interaction

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 2, Story 2.5]
- [Source: _bmad-output/planning-artifacts/architecture.md — Recovery Mode, Daemon Lifecycle, Config Management]
- [Source: _bmad-output/planning-artifacts/prd.md — FR17, FR18, FR19b, FR19c]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR19 confirmation pattern]
- [Source: familiar/lib/familiar/daemon/recovery.ex:67 — "Full backup/restore comes in Story 2.5"]
- [Source: familiar/lib/familiar/knowledge/knowledge.ex:167-169 — health/0 stub]
- [Source: familiar/lib/familiar/daemon/paths.ex — directory structure]

## Senior Developer Review (AI)

Date: 2026-04-02
Outcome: Changes Requested
Layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor (all completed)
Dismissed: 14 findings (false positives, pre-existing, handled elsewhere)

### Review Findings

- [x] [Review][Decision] D1: `--json` implicitly skips restore confirmation — kept as-is (convenience for scripts/agents)
- [x] [Review][Decision] D2: `fam status` not wired to health metrics — added `fam status` command with knowledge health
- [x] [Review][Patch] P1: `File.stat!` crash after successful backup — replaced with `File.stat/1`
- [x] [Review][Patch] P2: `Backup.list/1` unhandled `File.ls` errors — catch-all `{:error, _reason}` clause
- [x] [Review][Patch] P3: `compute_staleness_ratio` TOCTOU division by zero — guard against empty entries
- [x] [Review][Patch] P4: `auto_restore_from_backup` not fail-open — returns `:ok` always (fail-open)
- [x] [Review][Patch] P5: Auto-restore log message missing backup date — interpolates timestamp from path
- [x] [Review][Patch] P6: Quiet mode for backup list returns "ok" — added `backups:N` quiet summary
- [x] [Review][Defer] W1: No safety backup before restore overwrites DB [backup.ex:94] — deferred, enhancement
- [x] [Review][Defer] W2: `compute_staleness_ratio` loads all entries into memory [knowledge.ex:206] — deferred, pre-existing N+1 pattern (same as W5 from 2.4)
- [x] [Review][Defer] W3: `fam restore` no interactive selection flow [main.ex:302] — deferred, CLI-first non-interactive design
- [x] [Review][Defer] W4: Ambiguous timestamp substring match in `run_restore` [main.ex:322] — deferred, acceptable for MVP
- [x] [Review][Defer] W5: `prune/1` accepts retention:0, could delete all backups [backup.ex:127] — deferred, internal API only

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Created `Familiar.Knowledge.Backup` module with create/list/restore/latest/prune operations
- Added `Paths.backups_dir/0` for `.familiar/backups/` path resolution
- Wired auto-restore into `Recovery.check_database_integrity/0` — on integrity failure, attempts restore from latest backup; fail-open if no backup or restore fails
- Replaced `Knowledge.health/0` stub with real implementation: entry_count, type breakdown, staleness_ratio (via Freshness.validate_entries), last_refresh, backup status, green/amber/red signal
- Added CLI commands: `fam backup`, `fam restore`, `fam restore <timestamp>`, `fam context --health`
- Restore confirmation via injectable `confirm_fn` (UX-DR19); skipped with `--force` or `--json`
- Added `--health` and `--force` to OptionParser strict list
- Text formatters for health report (signal icon, type breakdown), backup result (path + size), restore list, backup size formatting
- Quiet summaries: `backup:<path>`, `restored:<filename>`, `health:<signal>:<count>`
- Error messages: backup_failed, restore_failed, no_backups, cancelled
- 37 new tests across 3 test files; full suite: 486 tests, 4 properties, 0 failures
- Credo strict: 0 issues

### Change Log

- 2026-04-02: Story implemented — backup/restore/health (all 6 tasks complete)

### File List

New files:
- familiar/lib/familiar/knowledge/backup.ex
- familiar/test/familiar/knowledge/backup_test.exs

Modified files:
- familiar/lib/familiar/daemon/paths.ex (added backups_dir/0)
- familiar/lib/familiar/daemon/recovery.ex (wired auto-restore)
- familiar/lib/familiar/knowledge/knowledge.ex (implemented health/0, module-level import Ecto.Query)
- familiar/lib/familiar/cli/main.ex (backup/restore/health commands, formatters, help text)
- familiar/lib/familiar/cli/output.ex (quiet summaries, error messages)
- familiar/test/familiar/daemon/recovery_test.exs (auto-restore test)
- familiar/test/familiar/knowledge/knowledge_test.exs (health tests)
- familiar/test/familiar/cli/main_test.exs (CLI tests for backup/restore/health)
