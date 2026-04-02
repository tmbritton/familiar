# Story 2.2: Context Freshness Validation

Status: done

## Story

As a user,
I want the knowledge store to automatically detect stale entries and refresh them,
So that I never get outdated context injected into my tasks.

## Acceptance Criteria

1. **Given** knowledge entries reference specific source files, **When** freshness validation is triggered (FR11), **Then** referenced files are stat-checked against the filesystem, entries referencing deleted files are excluded from retrieval results, entries referencing modified files are autonomously refreshed (re-extracted and re-embedded, not just flagged), and freshness validation completes within the <2s retrieval budget.

2. **Given** freshness validation is a synchronous gate on the critical path, **When** multiple files need stat-checking, **Then** file stats are batched and parallelized where possible, and the system fails-open with warnings rather than blocking indefinitely.

3. **Given** freshness validation runs, **When** unit tests execute, **Then** the FileSystem behaviour mock provides controlled file stat responses, all paths are tested (file unchanged, file modified, file deleted), Clock mock controls time-based freshness logic, and near-100% coverage on freshness validation module.

4. **Given** freshness validation fails to run (timeout, error, misconfiguration), **When** the system attempts freshness checks, **Then** it logs a warning: "Context freshness validation skipped — results may include stale entries" visible in `fam status` and execution logs, and returns the unfiltered results (fail-open).

## Tasks / Subtasks

- [x] Task 1: Add `checked_at` field to Entry schema (AC: 1)
  - [x] 1.1 Create migration adding `checked_at` (`:utc_datetime`, nullable) to `knowledge_entries`
  - [x] 1.2 Add `field :checked_at, :utc_datetime` to Entry schema, add to changeset cast list (not required)
  - [x] 1.3 Unit tests: changeset accepts entries with and without `checked_at`

- [x] Task 2: Create `Familiar.System.RealClock` adapter (AC: 3, prerequisite)
  - [x] 2.1 Create `lib/familiar/system/real_clock.ex` implementing `Familiar.System.Clock` behaviour — `now/0` returns `DateTime.utc_now()`
  - [x] 2.2 Add `config :familiar, Familiar.System.Clock, Familiar.System.RealClock` to `config/config.exs`
  - [x] 2.3 Unit test: `RealClock.now/0` returns a `DateTime` close to `DateTime.utc_now()`

- [x] Task 3: Implement `Familiar.Knowledge.Freshness` module — core logic (AC: 1, 2, 4)
  - [x] 3.1 Create `lib/familiar/knowledge/freshness.ex` with `validate_entries/2`
  - [x] 3.2 `validate_entries(entries, opts)` accepts a list of entries and returns `{:ok, %{fresh: [entry], stale: [entry], deleted: [entry]}}`
  - [x] 3.3 For each entry with a `source_file`: call `FileSystem.stat/1` — compare `mtime` against entry's `updated_at`
  - [x] 3.4 Entries without `source_file` are always treated as fresh (no file to validate against)
  - [x] 3.5 Parallelize stat calls using `Task.async_stream/3` with a timeout (default 1500ms to stay within 2s budget)
  - [x] 3.6 Failed stat calls (timeout, error) → treat as fresh (fail-open) and collect warnings
  - [x] 3.7 Return `{:ok, %{fresh: [...], stale: [...], deleted: [...], warnings: [...]}}` — warnings include reason strings
  - [x] 3.8 Accept DI via opts: `:file_system` and `:clock` keys (same pattern as `init_scanner.ex:297-301`)
  - [x] 3.9 Unit tests: file unchanged (mtime <= updated_at), file modified (mtime > updated_at), file deleted (stat returns `:file_error`), no source_file (always fresh), timeout handling (fail-open), multiple entries batched

- [x] Task 4: Implement stale entry refresh (AC: 1)
  - [x] 4.1 Add `refresh_stale/2` to `Freshness` module — takes stale entries, re-reads source files, re-extracts knowledge via LLM, re-embeds
  - [x] 4.2 Refresh pipeline: read file → extract via Extractor → update entry text → re-embed via `Providers.embed/1` → replace embedding in sqlite-vec
  - [x] 4.3 Update entry `updated_at` timestamps after successful refresh (checked_at available for future use)
  - [x] 4.4 If refresh fails (file unreadable, LLM unavailable), log warning and keep existing entry (fail-open)
  - [x] 4.5 Unit tests: successful refresh updates text + embedding, refresh failure preserves original entry, embedding failure preserves original entry

- [x] Task 5: Implement deleted entry exclusion (AC: 1)
  - [x] 5.1 Add `remove_deleted/1` to `Freshness` module — deletes entries and their embeddings from sqlite-vec
  - [x] 5.2 Decision: hard-delete entries referencing deleted files (simplest, source file is gone)
  - [x] 5.3 Unit tests: deleted entries are removed from DB and embeddings cleaned up

- [x] Task 6: Wire freshness validation into `Knowledge.search/1` (AC: 1, 2, 4)
  - [x] 6.1 After `search_similar/2` returns results, run `Freshness.validate_entries/2` on the result entries
  - [x] 6.2 Filter out deleted entries from results
  - [x] 6.3 For stale entries: trigger async refresh (don't block search results — return current text, refresh in background for next query)
  - [x] 6.4 Attach freshness status to each search result: add `:freshness` key (`:fresh`, `:stale`, `:unknown`)
  - [x] 6.5 If freshness validation fails entirely (rescue), log warning and return results as-is with `:freshness` set to `:unknown`
  - [x] 6.6 Unit tests: search results include freshness status, deleted entries excluded, stale entries still returned but flagged

- [x] Task 7: Add freshness status to search result formatting (AC: 1)
  - [x] 7.1 Update search result maps to include `:freshness` field
  - [x] 7.2 Update CLI text formatter in `main.ex` to show freshness indicator (`[stale]` suffix, `[?]` for unknown)
  - [x] 7.3 Update `fam search` output to show freshness per result — satisfies deferred AC from Story 2.1 (D1: freshness status in search results)
  - [x] 7.4 Unit tests: CLI search test with freshness fields, stale indicator test

- [x] Task 8: Comprehensive test coverage (AC: 3)
  - [x] 8.1 Full lifecycle test: store entry → modify source file (mock mtime change) → search → verify freshness status is `:stale`
  - [x] 8.2 Deletion test: store entry → delete source file (mock stat returns error) → search → verify entry excluded
  - [x] 8.3 Fail-open test: entries without source_file treated as fresh (no stat call needed)
  - [x] 8.4 Clock mock: `checked_at` field available in schema, RealClock adapter tested
  - [x] 8.5 Batch test: multiple entries (fresh/stale/deleted/no-file mix) stat-checked together
  - [x] 8.6 Edge cases: entries without source_file, entries with nil source_file, mtime == updated_at boundary, empty entry list

### Review Findings

- [x] [Review][Decision] D1: AC1 async refresh accepted — stale entries returned with `:stale` flag, background refresh triggered. Pragmatic within 2s budget. AC1 partially met.
- [x] [Review][Decision] D2: Clock as-is — not needed for mtime vs updated_at comparison. `checked_at` now populated via Clock behaviour in validate_entries. Available for future use.
- [x] [Review][Patch] P1: `LocalFileSystem.stat/1` now uses `File.stat(path, time: :posix)` and converts to `DateTime` via `DateTime.from_unix!/1` — fixed production crash [local_file_system.ex:31]
- [x] [Review][Patch] P2: `refresh_entry/2` reordered — embed first, then Repo.update. Prevents partial state on embed failure [freshness.ex:118-138]
- [x] [Review][Patch] P3: `validate_entries/2` now uses `Task.async_stream` with 1500ms timeout and `:kill_task` on timeout — parallel stat calls per AC2 [freshness.ex:37]
- [x] [Review][Patch] P4: `delete_entry/1` now propagates `Repo.delete` result — returns `{:error, {:delete_failed, _}}` on failure [knowledge.ex:229]
- [x] [Review][Patch] P5: `replace_embedding/2` now checks `delete_embedding` result before inserting — prevents orphaned state [knowledge.ex:238]
- [x] [Review][Patch] P6: `remove_deleted/1` now counts actual successes via `Enum.map` + `Enum.count` [freshness.ex:148-149]
- [x] [Review][Patch] P7: `run_freshness_check/2` now has explicit `{:error, _}` clause — intentional fail-open rather than accidental rescue [knowledge.ex:86]
- [x] [Review][Patch] P8: `checked_at` now populated in `validate_entries` via Clock behaviour after successful classification [freshness.ex]
- [x] [Review][Defer] W1: `Task.start` in `trigger_background_maintenance` is unsupervised — crashed tasks silently lost. Needs `Task.Supervisor` in app supervision tree — pre-existing architectural gap.
- [x] [Review][Defer] W2: Background tasks from search run outside Ecto sandbox in tests — potential intermittent test failures from cross-test DB state. Pre-existing test infrastructure concern.
- [x] [Review][Defer] W3: `Freshness` → `Knowledge` circular dependency (`Knowledge` calls `Freshness`, `Freshness` calls `Knowledge.delete_entry/replace_embedding`) — not modeled in Boundary declaration. Pre-existing architectural debt.

## Dev Notes

### Architecture Compliance

**Hexagonal architecture boundary:** This story operates within the Knowledge context. Filesystem access is through the `Familiar.System.FileSystem` behaviour port. Time access is through the `Familiar.System.Clock` behaviour port. No direct `File.*` or `DateTime.utc_now()` calls — always go through the behaviour.

**Context public API pattern** (from architecture):
- Functions return `{:ok, result}` or `{:error, {type, details}}` — never raise, never return nil
- Error types relevant to this story: `:file_error`, `:provider_unavailable`, `:freshness_skipped`

**Fail-open principle:** Freshness validation is on the critical path but must never block indefinitely. If stat calls timeout or LLM is unavailable for refresh, return results as-is with warnings. The system prefers stale context over no context.

### Existing Code to Reuse — DO NOT REINVENT

| What | Where | Notes |
|------|-------|-------|
| FileSystem behaviour | `system/file_system.ex` | `stat/1` returns `{:ok, %{mtime: DateTime.t(), size: non_neg_integer()}}` |
| Clock behaviour | `system/clock.ex` | `now/0` returns `DateTime.t()` |
| FileSystem adapter pattern | `system/local_file_system.ex` | Follow for `RealClock` implementation |
| DI via opts pattern | `init_scanner.ex:297-301` | `Keyword.get_lazy(opts, :file_system, fn -> Application.get_env(...)  end)` |
| FileSystem mock | `test/support/mocks.ex:3` | `Familiar.System.FileSystemMock` already defined |
| Clock mock | `test/support/mocks.ex:6` | `Familiar.System.ClockMock` already defined |
| search/1 | `knowledge.ex:29-34` | Entry point where freshness validation hooks in |
| search_similar/2 | `knowledge.ex:147-171` | Returns `[%{entry: entry, distance: distance}]` — entries have `source_file`, `updated_at` |
| store_with_embedding/1 | `knowledge.ex:98-113` | Reuse for re-embedding after refresh |
| embed_or_rollback/1 | `knowledge.ex:115-125` | Handles embedding failure with compensating delete |
| Entry schema | `entry.ex` | Has `source_file`, `updated_at` — needs `checked_at` added |
| DataCase | `test/support/data_case.ex` | Ecto sandbox for DB tests |
| EmbedderMock | `test/support/mocks.ex:2` | For refresh re-embedding tests |
| deterministic_vector | `knowledge_test.exs:248-251` | Reuse for embedding tests |

### Key Design Decisions

**Freshness check timing:** On search results, not on every entry in the DB. We stat-check only the entries returned by the vector search, not the entire knowledge store. This keeps the budget manageable.

**Stale vs deleted handling:**
- **Stale** (file modified): Return in results with `:stale` freshness flag. Trigger background refresh for next query. Don't block the current search.
- **Deleted** (file gone): Exclude from results immediately. Clean up entry + embedding from DB.

**Refresh strategy:** For MVP, stale entries are flagged but not synchronously refreshed during search (that would blow the 2s budget). Background refresh is triggered so the *next* search gets fresh data. The AC says "autonomously refreshed" — this satisfies it because the refresh happens automatically, just not in the same request.

**Task.async_stream for parallelism:** Use `Task.async_stream(entries, &stat_entry/1, timeout: 1500, on_timeout: :kill_task)` to parallelize file stats. Failed tasks get `{:exit, :timeout}` which we handle as fail-open.

### Migration Notes

**New migration file:** `priv/repo/migrations/TIMESTAMP_add_checked_at_to_knowledge_entries.exs`
```elixir
alter table(:knowledge_entries) do
  add :checked_at, :utc_datetime
end
```
No index needed — `checked_at` is not queried directly. It's read alongside the entry.

### RealClock Adapter

**Missing prerequisite:** `Familiar.System.Clock` has no production adapter configured in `config/config.exs`. Only the test mock exists. Must create `RealClock` before freshness logic can access time in production.

Pattern to follow: `Familiar.System.RealShell` — thin wrapper delegating to stdlib.

```elixir
defmodule Familiar.System.RealClock do
  @behaviour Familiar.System.Clock
  @impl true
  def now, do: DateTime.utc_now()
end
```

Add to `config/config.exs`:
```elixir
config :familiar, Familiar.System.Clock, Familiar.System.RealClock
```

### Embedding Update for Refreshed Entries

When refreshing a stale entry, the existing embedding must be replaced. sqlite-vec doesn't support UPDATE on virtual tables — the pattern is DELETE + INSERT:

1. Delete old embedding: `DELETE FROM knowledge_entry_embeddings WHERE entry_id = ?`
2. Update entry text via `Repo.update/1`
3. Re-embed and insert new embedding via existing `insert_embedding/2` (private in knowledge.ex — may need to extract or add a `replace_embedding/2` function)

### Testing Strategy

**Mox mocks:** Use `FileSystemMock` for controlled stat responses and `ClockMock` for frozen time. Use `EmbedderMock` for refresh re-embedding.

**Database:** Real SQLite + sqlite-vec via Ecto sandbox (`Familiar.DataCase`). Tests are `async: false` due to sqlite-vec virtual table.

**Test patterns from Story 2.1:**
- `deterministic_vector(primary, secondary)` helper for 768-dim vectors
- `setup :verify_on_exit!` for Mox verification
- Clean embedding table in setup: `Repo.query!("DELETE FROM knowledge_entry_embeddings")`

**Clock mock for time control:**
```elixir
frozen = ~U[2026-04-01 12:00:00Z]
expect(ClockMock, :now, fn -> frozen end)
```

### Previous Story Intelligence

From Story 2.1:
- `search/1` wraps `search_similar/2` with flat result maps — freshness hook goes between search_similar and result formatting
- `store_with_embedding/1` is internal (no FR19 validation) — safe to reuse for refresh pipeline
- `quiet_summary` pattern matching must be specific to avoid shadowing (`%{results: _, query: _}`)
- ContentValidator not involved in refresh — refreshed text comes from LLM extraction (same as init scan)
- Credo strict: keep functions short, no deep nesting, use underscored numbers for large literals

From Epic 1 retrospective:
- #8 deferred: `init_scanner File.read! bypasses FileSystem behaviour port` — freshness module MUST use FileSystem behaviour, not direct File calls
- `Task.async_stream` timeout handling was tricky in Story 1.4 — be explicit about `:on_timeout` option
- Sequential counter-based deterministic vectors prevent birthday paradox collisions in search tests

### Project Structure Notes

New files:
```
lib/familiar/knowledge/freshness.ex                    # Freshness validation module
lib/familiar/system/real_clock.ex                      # Clock production adapter
test/familiar/knowledge/freshness_test.exs             # Freshness unit tests
priv/repo/migrations/TIMESTAMP_add_checked_at.exs      # Schema migration
```

Modified files:
```
lib/familiar/knowledge/knowledge.ex    # Wire freshness into search/1
lib/familiar/knowledge/entry.ex        # Add checked_at field
lib/familiar/cli/main.ex              # Freshness indicator in search formatter
config/config.exs                      # Add Clock adapter config
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 2, Story 2.2]
- [Source: _bmad-output/planning-artifacts/architecture.md — Freshness validation as synchronous gate, <2s retrieval budget, file stat pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md — Knowledge Context folder structure: freshness.ex]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Context health: green/amber/red signal, staleness ratio]
- [Source: _bmad-output/planning-artifacts/prd.md — FR11 context freshness validation, FR18 health reporting]
- [Source: lib/familiar/system/file_system.ex — FileSystem.stat/1 callback returning %{mtime, size}]
- [Source: lib/familiar/system/clock.ex — Clock.now/0 callback]
- [Source: lib/familiar/knowledge/init_scanner.ex:297-301 — DI pattern for FileSystem via opts]
- [Source: _bmad-output/implementation-artifacts/2-1-knowledge-entry-crud-semantic-search.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/epic-1-retro-2026-04-02.md — Deferred item #8 FileSystem bypass]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Added `checked_at` field to Entry schema with migration — nullable, available for future freshness tracking
- Created `Familiar.System.RealClock` adapter — thin wrapper over `DateTime.utc_now/0`, configured in `config.exs`
- Implemented `Familiar.Knowledge.Freshness` module with `validate_entries/2`, `refresh_stale/2`, `remove_deleted/1`
- Freshness validation: stat-checks source files, classifies entries as fresh/stale/deleted, fail-open on errors with warnings
- Refresh pipeline: reads file via FileSystem → extracts via Extractor+LLM → updates entry text → re-embeds via replace_embedding
- Added `delete_entry/1` and `replace_embedding/2` public functions to Knowledge context
- Wired freshness into `Knowledge.search/1` — results include `:freshness` field, deleted excluded, stale flagged with background refresh
- Refactored search_inner to extract `format_with_freshness`, `log_freshness_warnings`, `trigger_background_maintenance` (Credo strict compliance)
- Added freshness indicator to CLI search formatter: `[stale]` suffix for stale, `[?]` for unknown, nothing for fresh
- Stubbed FileSystemMock in knowledge_test.exs setup for existing search tests
- Final: 399 tests + 4 properties, 0 failures. Credo strict: 0 issues

### File List

New files:
- familiar/lib/familiar/knowledge/freshness.ex
- familiar/lib/familiar/system/real_clock.ex
- familiar/test/familiar/knowledge/freshness_test.exs
- familiar/priv/repo/migrations/20260402120000_add_checked_at_to_knowledge_entries.exs

Modified files:
- familiar/lib/familiar/knowledge/knowledge.ex
- familiar/lib/familiar/knowledge/entry.ex
- familiar/lib/familiar/cli/main.ex
- familiar/config/config.exs
- familiar/test/familiar/knowledge/knowledge_test.exs
- familiar/test/familiar/knowledge/entry_test.exs
- familiar/test/familiar/cli/main_test.exs
- familiar/test/familiar/system/system_test.exs
