# Story 2.4: Knowledge Store Management

Status: done

## Story

As a user,
I want to inspect, edit, delete, and re-scan knowledge entries,
So that I can curate the knowledge store and fix incorrect information.

## Acceptance Criteria

1. **Given** knowledge entries exist in the store, **When** the user runs `fam search` and selects an entry, **Then** the full entry is displayed: content, type, source, freshness status, referenced files, creation date (FR14), **And** the user can edit the entry content (entry is re-embedded after edit), **And** the user can delete the entry, **And** user-created and user-edited entries are tagged with source type "user".

2. **Given** the user wants to refresh the knowledge store, **When** `fam context --refresh [path]` is run (FR15), **Then** the system re-scans the specified path (or full project if no path), **And** user-created and user-edited entries are preserved — only auto-generated entries are updated, **And** new files are indexed, deleted files' entries are removed.

3. **Given** the user wants to consolidate redundant entries, **When** `fam context --compact` is run (FR16), **Then** semantically similar entries are identified and presented for consolidation, **And** the user confirms which entries to merge, **And** merged entries retain the most complete information.

4. **Given** management operations are implemented, **When** unit tests run, **Then** edit-and-re-embed, delete, re-scan with user entry preservation, and consolidation are all tested, **And** near-100% coverage on management functions.

## Tasks / Subtasks

- [x] Task 1: Add `fam entry <id>` command — inspect a single entry (AC: 1)
  - [x] 1.1 Add `run_with_daemon({"entry", [id_string], _}, deps)` to `CLI.Main` — calls `Knowledge.fetch_entry/1`
  - [x] 1.2 Return full entry map: id, text, type, source, source_file, metadata (parsed), freshness status, inserted_at, updated_at
  - [x] 1.3 Add text formatter in `CLI.Main.text_formatter("entry")` — human-readable display with labeled fields
  - [x] 1.4 Add quiet summary: `"entry:#{id}"`
  - [x] 1.5 Add error message for `:not_found` in `CLI.Output`
  - [x] 1.6 Update help text with `entry <id>` command
  - [x] 1.7 Unit tests: valid ID returns entry, invalid ID returns not_found, JSON/text/quiet output modes

- [x] Task 2: Add `fam edit <id>` command — edit entry text with re-embed (AC: 1)
  - [x] 2.1 Create `Knowledge.update_entry/2` in `knowledge.ex` — accepts entry and new attrs map
  - [x] 2.2 `update_entry/2` pipeline: validate content (FR19 knowledge-not-code) → update entry via `Entry.changeset/2` → re-embed new text → `replace_embedding/2` — embed-before-persist order
  - [x] 2.3 When user edits, set `source: "user"` on the entry (tag user-edited entries)
  - [x] 2.4 Add `run_with_daemon({"edit", [id_string, new_text], _}, deps)` to `CLI.Main` — joins remaining args as new text
  - [x] 2.5 Add text formatter, quiet summary ("edited:#{id}"), error messages
  - [x] 2.6 Update help text with `edit <id> <text>` command
  - [x] 2.7 Unit tests: edit updates text and re-embeds, source changes to "user", FR19 rejects code content, missing entry returns not_found

- [x] Task 3: Add `fam delete <id>` command — delete entry and embedding (AC: 1)
  - [x] 3.1 Add `run_with_daemon({"delete", [id_string], _}, deps)` to `CLI.Main` — calls `Knowledge.fetch_entry/1` then `Knowledge.delete_entry/1`
  - [x] 3.2 No confirmation prompt — matches UX-DR19 (only `fam restore` requires confirmation; all other actions run immediately)
  - [x] 3.3 Add text formatter, quiet summary ("deleted:#{id}"), error messages
  - [x] 3.4 Update help text with `delete <id>` command
  - [x] 3.5 Unit tests: delete removes entry and embedding, missing entry returns not_found, JSON/text/quiet modes

- [x] Task 4: Add `fam context --refresh [path]` command — re-scan (AC: 2)
  - [x] 4.1 Create `Knowledge.Management` module in `lib/familiar/knowledge/management.ex`
  - [x] 4.2 Implement `Management.refresh/2` — accepts project_dir and optional path filter
  - [x] 4.3 Refresh pipeline: scan files (reuse `InitScanner.scan_files/2`) → for each file, check if entries exist with that `source_file` → if entry exists AND `source != "user"`: re-extract, re-embed, update entry → if no entry: create new entry via `store_with_embedding/1` → if entry source is "user": skip (preserve user entries)
  - [x] 4.4 Remove entries for deleted files: query entries by source_file, stat each file, delete entries where file no longer exists (same logic as `Freshness.remove_deleted/1` but for all non-user entries)
  - [x] 4.5 Accept optional path filter — if provided, only scan files under that path; only process entries with matching source_file prefix
  - [x] 4.6 Add `run_with_daemon({"context", args, %{refresh: true}}, deps)` to `CLI.Main` — parse `--refresh` flag via OptionParser
  - [x] 4.7 Return summary: `%{scanned: n, updated: n, created: n, removed: n, preserved: n}`
  - [x] 4.8 Add text formatter, quiet summary, error messages
  - [x] 4.9 Unit tests: full re-scan updates auto entries, preserves user entries, indexes new files, removes deleted file entries, path filter restricts scope

- [x] Task 5: Add `fam context --compact` command — consolidate duplicates (AC: 3)
  - [x] 5.1 Implement `Management.find_consolidation_candidates/1` — query all entries, for each pair within same type, compute semantic similarity via `search_similar/2`, return pairs with cosine distance < 0.3
  - [x] 5.2 Implement `Management.compact/2` — accepts list of entry ID pairs to merge, for each pair: combine text (keep the longer/more complete entry, append unique info from the other), re-embed merged text, delete the shorter entry
  - [x] 5.3 `compact/2` returns the merged entries and delete count
  - [x] 5.4 CLI integration: `fam context --compact` calls `find_consolidation_candidates/1`, displays pairs to user, accepts user selection (all, specific indices, none), then calls `compact/2`
  - [x] 5.5 For `--json` mode: return candidates array with pair IDs, texts, similarity scores — let caller decide
  - [x] 5.6 Unit tests: finds similar entries as candidates, merges correctly, preserves longer text, re-embeds after merge, no candidates when entries are dissimilar

- [x] Task 6: Comprehensive test coverage (AC: 4)
  - [x] 6.1 CLI integration tests for all new commands: entry, edit, delete, context --refresh, context --compact
  - [x] 6.2 Knowledge.update_entry/2 unit tests: happy path, validation errors, embed failures
  - [x] 6.3 Management.refresh/2 unit tests: full and filtered re-scan, user entry preservation, new file indexing, deleted file cleanup
  - [x] 6.4 Management.compact/2 unit tests: candidate detection, merging logic, edge cases (no candidates, single entry)
  - [x] 6.5 Edge cases: empty knowledge store, all entries are user-created, all entries deleted

### Senior Developer Review (AI)

Review date: 2026-04-02
Review outcome: Changes Requested
Layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor (all completed)
Dismissed: 14 findings (false positives, style, pre-existing patterns, duplicate findings)

### Review Follow-ups (AI)

- [x] [AI-Review][Decision] D1: `format_entry_detail` now includes freshness status via `Freshness.validate_entries/2` — user chose option 1 (add freshness)
- [x] [AI-Review][Decision] D2: `--compact` CLI now supports `--apply <indices>` for programmatic merge execution — user chose option 2
- [x] [AI-Review][Decision] D3: `refresh_entries` now maps extracted entries to existing entries by type, creates new entries when type doesn't match — user chose option 2
- [x] [AI-Review][Patch] P1: `--refresh`, `--compact`, `--apply` registered in OptionParser strict list. Context command uses `flags` map only. [main.ex:36-45]
- [x] [AI-Review][Patch] P2: LIKE wildcards (`%`, `_`) escaped in `load_existing_entries` via `escape_like/1`. [management.ex:112-120]
- [x] [AI-Review][Patch] P3: `update_entry` compensates on `replace_embedding` failure — reverts entry text/source to original values. [knowledge.ex:147-168]
- [x] [AI-Review][Patch] P4: `remove_orphaned_entries` only deletes when `fs.stat` returns `{:error, :enoent}` — transient errors no longer cause data loss. [management.ex:214]
- [x] [AI-Review][Defer] W1: `find_consolidation_candidates` issues N+1 queries — one `search_similar` per entry. Scales poorly for large stores. — deferred, optimization for post-MVP
- [x] [AI-Review][Defer] W2: `merge_pair` naive text concatenation — appends shorter text to longer without deduplication. Could produce redundant merged text. — deferred, semantic merge is an enhancement
- [x] [AI-Review][Defer] W3: `compact` returns `{:ok, _}` even when all merges fail — no way to distinguish total failure. — deferred, error propagation enhancement
- [x] [AI-Review][Defer] W4: TOCTOU between fetch and update/delete — concurrent operations could race. — deferred, pre-existing architectural limitation (same as W1 from Story 2.3)
- [x] [AI-Review][Defer] W5: No pagination in `load_existing_entries` — loads all entries into memory. — deferred, optimization for large projects

## Dev Notes

### Architecture Compliance

**Hexagonal architecture boundary:** This story operates within the Knowledge context. LLM access through `Familiar.Providers.LLM` and `Familiar.Providers.Embedder` behaviour ports. File system access through `Familiar.System.FileSystem` behaviour. No direct HTTP calls.

**Context public API pattern** (from architecture):
- Functions return `{:ok, result}` or `{:error, {type, details}}` — never raise, never return nil
- Error types relevant: `:not_found`, `:validation_failed`, `:knowledge_not_code`, `:provider_unavailable`

**CLI output contract:**
- JSON: `{"data": ...}` / `{"error": {"type": "...", "message": "...", "details": {...}}}`
- Text: human-readable via command-specific text formatters
- Quiet: minimal one-line summary for scripting
- All commands support `--json` and `--quiet` per FR78

**UX-DR19:** Only `fam restore` requires confirmation. Delete runs immediately — no confirmation prompt needed.

### Existing Code to Reuse — DO NOT REINVENT

| What | Where | Notes |
|------|-------|-------|
| Knowledge.fetch_entry/1 | `knowledge.ex:112-120` | Fetch by ID — returns `{:ok, entry}` or `{:error, {:not_found, _}}` |
| Knowledge.delete_entry/1 | `knowledge.ex:234-241` | Delete entry + embedding. Already handles embedding cleanup |
| Knowledge.store_with_embedding/1 | `knowledge.ex:154-168` | For new entries during refresh (bypasses FR19 since auto-generated) |
| Knowledge.replace_embedding/2 | `knowledge.ex:249-254` | Replace embedding after edit |
| Knowledge.search_similar/2 | `knowledge.ex:202-226` | For finding consolidation candidates |
| ContentValidator.validate_not_code/1 | `content_validator.ex` | FR19 validation for user edits |
| Entry.changeset/2 | `entry.ex:27-34` | Validates types, sources, JSON metadata |
| Freshness.validate_entries/2 | `freshness.ex:30` | Get freshness status for entry display |
| Freshness.remove_deleted/1 | `freshness.ex:161-165` | Pattern for deleting entries of missing files |
| InitScanner.scan_files/2 | `init_scanner.ex:30-67` | Reuse file discovery during refresh |
| Extractor.extract_from_file/1 | Referenced in `freshness.ex:134` | Re-extract knowledge from source file |
| CLI.Main pattern | `main.ex:149-161` | Pattern for adding new commands (see `search` command) |
| CLI.Output.format/3 | `output.ex:27` | Formatting pipeline — JSON/text/quiet |
| Output text_formatter pattern | `main.ex:272-339` | Pattern for command-specific text formatters |
| Output quiet_summary pattern | `output.ex:91-99` | Pattern for quiet mode output |
| Output error_message pattern | `output.ex:101-123` | Pattern for error messages |
| DI pattern | `freshness.ex:176-180` | `Keyword.get_lazy(opts, :key, fn -> Application.get_env(...) end)` |
| SecretFilter.filter/1 | `knowledge/secret_filter.ex` | Apply to text during re-scan extraction |

### Key Design Decisions

**Entry inspection:** `fam entry <id>` displays all fields including parsed metadata JSON (not raw JSON string). Include freshness status by calling `Freshness.validate_entries/2` on the single entry. This is a quick single-file stat check, negligible cost.

**Edit workflow:** `fam edit <id> <new text>` is non-interactive (CLI-first design per project context). Text is provided inline. Entry is re-embedded after edit (embed-before-persist: embed new text, then update entry + replace embedding). Source is changed to "user" to protect from future auto-refresh.

**Delete workflow:** No confirmation per UX-DR19. `fam delete <id>` immediately deletes entry + embedding via existing `Knowledge.delete_entry/1`.

**Refresh strategy:** Refresh reuses `InitScanner.scan_files/2` for file discovery, then for each file:
- If entries exist with `source != "user"` for that source_file: re-extract via `Extractor.extract_from_file/1`, update text, re-embed
- If no entries exist: create new via `store_with_embedding/1`
- If source is "user": skip entirely (preserve user curation)
- Query entries with source_files that no longer exist on disk: delete those entries (but NOT user-source entries — they may reference files that were deleted intentionally)

**Compact strategy:** Find all entry pairs with cosine distance < 0.3 AND same type. Present candidates with both texts and similarity score. User picks which to merge. Merge keeps the longer text entry, appends unique info from shorter, re-embeds, deletes the shorter entry. For `--json` mode, return candidate list without interactivity (for programmatic use by other agents per project CLI-first design).

**New Management module:** Create `Familiar.Knowledge.Management` for refresh and compact operations. These are administrative operations that don't fit cleanly in the main `Knowledge` module (which is the CRUD/search API). `update_entry/2` does belong in `Knowledge` since it's a core CRUD operation.

**OptionParser for context command:** The `context` command uses `--refresh` and `--compact` flags. Add these to the existing OptionParser in `CLI.Main.parse_args/1`. The `context` command dispatches based on which flag is present.

### Entry Source Protection Rules

| Source | Created By | Refresh Behavior | Delete Behavior |
|--------|-----------|------------------|-----------------|
| `init_scan` | Init scanner | Re-extract and update | Remove if file deleted |
| `post_task` | Hygiene loop | Re-extract and update | Remove if file deleted |
| `agent` | Agent operations | Re-extract and update | Remove if file deleted |
| `manual` | Direct API call | Re-extract and update | Remove if file deleted |
| `user` | User edit/create | **PRESERVE — skip refresh** | **Only manual delete** |

### Testing Strategy

**Mox mocks:** `EmbedderMock` for deterministic vectors during re-embed/search. `LLMMock` for extraction during refresh. `FileSystemMock` for controlled file stat/read during refresh. `ClockMock` for freshness checks.

**Database:** Real SQLite + sqlite-vec via Ecto sandbox (`Familiar.DataCase`). Tests are `async: false` due to sqlite-vec virtual table.

**CLI tests:** Follow pattern from `test/familiar/cli/main_test.exs` — inject deps map with mock functions, test return values (not IO output). Test all three output modes (JSON/text/quiet) for each new command.

**Test patterns from Stories 2.1-2.3:**
- `deterministic_vector(primary, secondary)` helper for 768-dim vectors
- `setup :verify_on_exit!` for Mox verification
- Clean embedding table in setup: `Repo.query!("DELETE FROM knowledge_entry_embeddings")`
- `Mox.set_mox_global()` for tests using `Task.async_stream`
- Stub `ClockMock` and `FileSystemMock` in setup for implicit freshness checks

### Previous Story Intelligence

From Story 2.3:
- `store_with_dedup/2` in `hygiene.ex` demonstrates the dedup pattern — reuse for compact candidate detection
- Embed-before-persist ordering critical (P1 fix) — apply same pattern in `update_entry/2`
- `increment_update_count/1` helper parses metadata JSON counter — may want similar metadata tracking for edit/merge operations
- Credo strict: keep functions short, no deep nesting (max 2 levels), alphabetize aliases

From Story 2.2:
- `Freshness.refresh_stale/2` at `freshness.ex:115-152` already re-extracts and re-embeds stale entries — reuse this pattern for refresh
- `Freshness.remove_deleted/1` at `freshness.ex:161-165` deletes entries for missing files — reuse for refresh cleanup
- `Task.async_stream` requires `Mox.set_mox_global()` — use `stub` not `expect` for parallel operations

From Story 2.1:
- `store/1` validates FR19 via `ContentValidator.validate_not_code/1` — user edits must go through this validation
- `store_with_embedding/1` bypasses FR19 — use for refresh auto-generated entries (same justification as init scan)
- `search_similar/2` returns `[%{entry: entry, distance: distance}]` — use for compact candidate detection

From Epic 1 retrospective:
- CLI test pattern: inject all dependencies via `deps` map for full testability
- Help text must be updated for every new command
- OptionParser flags must be added to `parse_args/1`

### CLI Command Summary

```
fam entry <id>              # Inspect single entry (FR14)
fam edit <id> <text>        # Edit entry text, re-embed, tag as "user" (FR14)
fam delete <id>             # Delete entry and embedding (FR14)
fam context --refresh       # Full project re-scan (FR15)
fam context --refresh path  # Scoped re-scan (FR15)
fam context --compact       # Find and consolidate duplicates (FR16)
```

### Project Structure Notes

New files:
```
lib/familiar/knowledge/management.ex              # Refresh and compact operations
test/familiar/knowledge/management_test.exs        # Management unit tests
```

Modified files:
```
lib/familiar/knowledge/knowledge.ex                # Add update_entry/2
lib/familiar/cli/main.ex                           # Add entry/edit/delete/context commands
lib/familiar/cli/output.ex                         # Add error messages for new errors
test/familiar/knowledge/knowledge_test.exs          # Add update_entry tests
test/familiar/cli/main_test.exs                    # Add CLI command tests
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 2, Story 2.4, lines 682-712]
- [Source: _bmad-output/planning-artifacts/prd.md — FR14 entry management, FR15 re-scan, FR16 consolidation, lines 486-488]
- [Source: _bmad-output/planning-artifacts/architecture.md — Knowledge context, lines 157-161]
- [Source: _bmad-output/planning-artifacts/architecture.md — Knowledge-not-code strategy, lines 486-498]
- [Source: _bmad-output/planning-artifacts/architecture.md — Project file structure, lines 759-764]
- [Source: lib/familiar/knowledge/knowledge.ex — fetch_entry/1, delete_entry/1, store_with_embedding/1, replace_embedding/2, search_similar/2]
- [Source: lib/familiar/knowledge/freshness.ex — refresh_stale/2, remove_deleted/1 patterns]
- [Source: lib/familiar/knowledge/init_scanner.ex — scan_files/2 for file discovery]
- [Source: lib/familiar/cli/main.ex — CLI command routing, text formatters, DI via deps map]
- [Source: lib/familiar/cli/output.ex — JSON envelope, quiet_summary, error_message patterns]
- [Source: lib/familiar/knowledge/entry.ex — valid_types, valid_sources including "user"]
- [Source: _bmad-output/implementation-artifacts/2-3-post-task-hygiene-loop.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/2-2-context-freshness-validation.md — Freshness patterns]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Credo strict found 10 issues after initial implementation: nested too deep (3), chained Enum.reject (2), redundant with clause (1), large number formatting (1), length/1 comparison (2), unused alias (1). All resolved by extracting helpers, merging reject predicates, simplifying with clauses, and cleaning up test assertions.

### Completion Notes List

- Created `Familiar.Knowledge.Management` module with `refresh/2`, `find_consolidation_candidates/1`, and `compact/2`
- Added `Knowledge.update_entry/2` — FR19 validated, embed-before-persist, supports source change to "user"
- Added CLI commands: `fam entry <id>`, `fam edit <id> <text>`, `fam delete <id>`, `fam context --refresh [path]`, `fam context --compact`
- All CLI commands support JSON/text/quiet output modes per FR78
- Refresh preserves user-source entries, updates auto-generated entries, creates for new files, removes orphaned entries
- Compact finds semantically similar pairs (cosine distance < 0.3, same type), merges keeping longer text
- Delete runs immediately without confirmation per UX-DR19
- Edit changes entry source to "user" to protect from future auto-refresh
- DI via opts for scan_fn and file_system in Management module for testability
- 29 new tests (14 management + 15 CLI), full suite: 455 tests, 0 failures, 4 properties. Credo strict: 0 issues.

### Change Log

- 2026-04-02: Implemented Story 2.4 — Knowledge Store Management (all 6 tasks)

### File List

New files:
- familiar/lib/familiar/knowledge/management.ex
- familiar/test/familiar/knowledge/management_test.exs

Modified files:
- familiar/lib/familiar/knowledge/knowledge.ex
- familiar/lib/familiar/cli/main.ex
- familiar/lib/familiar/cli/output.ex
- familiar/test/familiar/cli/main_test.exs
- _bmad-output/implementation-artifacts/2-4-knowledge-store-management.md
- _bmad-output/implementation-artifacts/sprint-status.yaml
