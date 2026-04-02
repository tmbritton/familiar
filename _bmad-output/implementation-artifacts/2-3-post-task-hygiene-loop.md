# Story 2.3: Post-Task Hygiene Loop

Status: done

## Story

As a user,
I want the system to automatically capture new knowledge after each task completes,
So that the knowledge store grows smarter with every task without manual intervention.

## Acceptance Criteria

1. **Given** a task has completed successfully (or succeeded after retry), **When** the post-task hygiene loop runs (FR12), **Then** new knowledge is extracted: facts discovered, decisions made, gotchas encountered, relationships found, domain knowledge is captured from the SUCCESSFUL execution only (not failed attempts), failure gotchas are captured from the FAILURE REASON (not failed code), entries referencing the same source file as new discoveries are compared — if the new entry supersedes the old (same topic, newer source), the old is replaced, and new entries are embedded asynchronously via the embedding worker pool.

2. **Given** the hygiene loop processes results, **When** it encounters knowledge that already exists in the store, **Then** it updates existing entries rather than creating duplicates.

3. **Given** hygiene loop is implemented, **When** unit tests run, **Then** knowledge extraction from success vs failure scenarios is tested, duplicate detection and update logic is covered, and near-100% coverage on hygiene module.

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Knowledge.Hygiene` module — core structure (AC: 1)
  - [x] 1.1 Create `lib/familiar/knowledge/hygiene.ex` with `run/2` function accepting execution context
  - [x] 1.2 Define execution context struct/map: `%{success_context: map(), failure_log: String.t() | nil, modified_files: [String.t()], task_id: integer()}`
  - [x] 1.3 `run/2` returns `{:ok, %{extracted: count, updated: count, skipped: count}}` or `{:error, {atom, map}}`
  - [x] 1.4 Accept DI via opts: `:file_system`, `:llm` keys (same pattern as `init_scanner.ex:297-301` and `freshness.ex`)

- [x] Task 2: Implement success knowledge extraction (AC: 1)
  - [x] 2.1 Create `extract_from_success/2` — takes successful execution context (modified files, agent conversation summary, decisions made)
  - [x] 2.2 Build extraction prompt for post-task context: "Given this task execution, extract facts, decisions, gotchas, and relationships. Focus on what was LEARNED, not what was CODED."
  - [x] 2.3 Valid entry types for hygiene extraction: `fact`, `decision`, `gotcha`, `relationship`, `convention` (NOT `file_summary` — that's init-scan only)
  - [x] 2.4 Set `source: "post_task"` for all hygiene-extracted entries
  - [x] 2.5 Apply `SecretFilter.filter/1` to extracted text before storage (consistent with Extractor)
  - [x] 2.6 Unit tests: successful extraction produces entries with correct types/sources, empty context produces no entries, secret values filtered

- [x] Task 3: Implement failure gotcha extraction (AC: 1)
  - [x] 3.1 Create `extract_from_failure/2` — takes failure log/reason (NOT failed code)
  - [x] 3.2 Build failure extraction prompt: "Given this task failure, extract gotchas and edge cases. Focus on what CONFUSED the agent, not the code that was wrong."
  - [x] 3.3 Only extract `gotcha` type entries from failures
  - [x] 3.4 Set `source: "post_task"` for failure-extracted entries
  - [x] 3.5 Unit tests: failure extraction produces gotcha entries, nil failure_log produces no entries, only gotcha type extracted (not decisions/facts)

- [x] Task 4: Implement duplicate detection and superseding (AC: 1, 2)
  - [x] 4.1 Create `detect_duplicates/2` — for each new entry, search existing entries by `source_file` and semantic similarity
  - [x] 4.2 Use `Knowledge.search_similar/2` to find entries with similar text (cosine distance < threshold)
  - [x] 4.3 If a matching entry exists with same `source_file` and similar topic: update existing entry text, re-embed, increment metadata counter
  - [x] 4.4 If no match: store as new entry via `Knowledge.store/1`
  - [x] 4.5 Threshold for "same topic": cosine distance < 0.3 AND same `source_file` — both conditions required
  - [x] 4.6 Unit tests: new entry stored when no match, existing entry updated when match found, entries with different source_files not considered duplicates, threshold boundary tests

- [x] Task 5: Wire hygiene into run pipeline (AC: 1)
  - [x] 5.1 Add `run/2` orchestration: extract from success → extract from failure → deduplicate/store each entry → return summary
  - [x] 5.2 Process entries sequentially (embedding pool is async internally via `store_with_embedding/1`)
  - [x] 5.3 Fail-open: if extraction fails (LLM unavailable), log warning and return `{:ok, %{extracted: 0, ...}}` — don't block task completion
  - [x] 5.4 Unit tests: full pipeline success → failure → store, LLM failure produces warning not error, combined success+failure extraction

- [x] Task 6: Comprehensive test coverage (AC: 3)
  - [x] 6.1 Success scenario: mock LLM returns extracted entries → verify stored with correct types/sources
  - [x] 6.2 Failure scenario: mock LLM returns gotcha → verify stored as gotcha type
  - [x] 6.3 Duplicate scenario: store entry → run hygiene with overlapping knowledge → verify update not duplicate
  - [x] 6.4 Mixed scenario: success entries + failure gotchas + duplicates in single run
  - [x] 6.5 Edge cases: empty execution context, LLM returns empty array, LLM returns invalid JSON, secret filtering

### Senior Developer Review (AI)

Review date: 2026-04-02
Review outcome: Changes Requested
Layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor (all completed)
Dismissed: 13 findings (spec-compliant design, false positives, internal-input-only concerns)

### Review Follow-ups (AI)

- [x] [AI-Review][Decision] D1: `update_existing` now also updates `type` field when superseding — user chose option 2 (trust LLM reclassification)
- [x] [AI-Review][Decision] D2: `update_existing` now increments `update_count` in metadata when superseding — user chose option 2 (implement counter)
- [x] [AI-Review][Patch] P1: `update_existing` reordered to embed-before-persist — `Providers.embed` runs first, then `Repo.update` + `replace_embedding`. Prevents inconsistent state on embed failure. [hygiene.ex:225-248]
- [x] [AI-Review][Patch] P2: `valid_hygiene_entry?` now uses `String.trim(text) != ""` to reject whitespace-only text. [hygiene.ex:198-200]
- [x] [AI-Review][Defer] W1: No concurrency control on dedup-then-update — concurrent hygiene runs could both find "no duplicate" and both insert. Unlikely until Epic 5 parallel task execution. — deferred, pre-existing architectural limitation
- [x] [AI-Review][Defer] W2: Embedding computed twice during dedup — `search_similar` embeds query text, then `store_with_embedding`/`update_existing` embeds again. Performance optimization opportunity. — deferred, optimization
- [x] [AI-Review][Defer] W3: AC1 says "embedded asynchronously via embedding worker pool" but pool doesn't exist yet — current implementation embeds synchronously like all other stories. — deferred, blocked by unimplemented infrastructure

## Dev Notes

### Architecture Compliance

**Hexagonal architecture boundary:** This story operates within the Knowledge context. LLM access through `Familiar.Providers.LLM` behaviour port. No direct HTTP calls or external system access.

**Context public API pattern** (from architecture):
- Functions return `{:ok, result}` or `{:error, {type, details}}` — never raise, never return nil
- Error types relevant to this story: `:provider_unavailable`, `:extraction_failed`

**Post-task hygiene architecture** (from architecture.md lines 207-210):
- Domain knowledge (conventions, decisions, relationships): capture from SUCCESSFUL execution only
- Failure gotchas (edge cases, ambiguities): capture from FAILURE REASON, not failed code
- Two extraction passes with different source material — success context and failure log

### Existing Code to Reuse — DO NOT REINVENT

| What | Where | Notes |
|------|-------|-------|
| Extractor.build_prompt/2 | `extractor.ex:70-93` | Reference for prompt structure — but hygiene needs different prompts |
| Extractor.parse_extraction_response/2 | `extractor.ex:96-117` | Reuse for parsing LLM JSON responses |
| SecretFilter.filter/1 | `knowledge/secret_filter.ex` | Apply to all extracted text before storage |
| Knowledge.store/1 | `knowledge.ex:74-84` | Public API with FR19 validation — use for new entries |
| Knowledge.store_with_embedding/1 | `knowledge.ex:99-113` | Internal — bypasses FR19. Use for hygiene entries since they come from LLM extraction (same as init scan) |
| Knowledge.search_similar/2 | `knowledge.ex:147-171` | For duplicate detection — find semantically similar entries |
| Knowledge.replace_embedding/2 | `knowledge.ex:239-243` | For updating existing entry embeddings |
| Entry.changeset/2 | `entry.ex:26-33` | Validates types, sources, JSON metadata |
| DI pattern | `freshness.ex:166-173` | `Keyword.get_lazy(opts, :key, fn -> Application.get_env(...) end)` |
| LLM mock | `test/support/mocks.ex:1` | `Familiar.Providers.LLMMock` |
| EmbedderMock | `test/support/mocks.ex:2` | `Familiar.Knowledge.EmbedderMock` |

### Key Design Decisions

**Hygiene extraction vs init-scan extraction:** Init-scan uses `Extractor.extract_from_file/1` which reads a source file and produces summaries. Hygiene extraction is different — it takes an execution context (what was done, what was decided, what failed) and produces knowledge entries. Different prompts, different valid types. Do NOT reuse `Extractor.extract_from_file/1` directly — create hygiene-specific extraction functions.

**Valid types for hygiene:** `fact`, `decision`, `gotcha`, `relationship`, `convention`. NOT `file_summary` (init-scan only). The `Extractor.valid_entry?/1` helper uses a hardcoded whitelist that excludes `fact` and `gotcha` — hygiene must use its own validation.

**Duplicate detection strategy:** Semantic similarity + same source_file. Use `Knowledge.search_similar/2` with a tight cosine distance threshold (< 0.3) to find potential duplicates. Both conditions (similar text AND same source_file) must match — semantic similarity alone is not enough (two different files could have similar conventions).

**Superseding logic:** When a duplicate is found, update the existing entry's text and re-embed. Don't delete and recreate — the entry ID should be stable for any references. Use `Repo.update/1` + `Knowledge.replace_embedding/2`.

**Source tagging:** All hygiene entries use `source: "post_task"`. This distinguishes them from `init_scan` entries and `user`/`agent` entries, enabling selective refresh/cleanup later.

**Fail-open:** Hygiene should never block task completion. If the LLM is unavailable or extraction fails, log a warning and return success with zero extracted entries. The knowledge store missing some entries is better than blocking the user.

### Execution Context Shape

The hygiene loop receives execution context after a task completes. For MVP, this is a map:

```elixir
%{
  # From successful execution
  success_context: %{
    task_summary: "Added session middleware with JWT validation",
    modified_files: ["lib/auth/session.ex", "lib/auth/jwt.ex"],
    decisions_made: "Chose cookie-based sessions for web, token-based for API",
    conversation_summary: "Agent identified conflicting patterns..."
  },
  # From failure (nil if no failures occurred)
  failure_log: "Session middleware has two conflicting patterns...",
  # Files modified by this task
  modified_files: ["lib/auth/session.ex"],
  # Task identifier
  task_id: 42
}
```

This shape will be finalized when Epic 5 (Task Execution) is implemented. For now, design the hygiene module to accept this map shape and test with mock data.

### Extraction Prompt Design

**Success extraction prompt:**
```
Given this task execution summary, extract knowledge entries as a JSON array.
Each entry must have "type", "text", and "source_file" fields.

Valid types: "fact", "decision", "gotcha", "relationship", "convention"

Rules:
- Extract what was LEARNED, not what was CODED
- Facts: concrete discoveries about the codebase
- Decisions: choices made and their rationale
- Gotchas: edge cases, surprising behaviors, things to watch out for
- Relationships: dependencies discovered, module interactions
- Conventions: patterns established or confirmed
- Do NOT include raw code snippets
- Do NOT include secret values
- Keep each entry concise (1-3 sentences)

Task summary: {task_summary}
Files modified: {modified_files}
Decisions: {decisions_made}

Respond with ONLY a JSON array of entry objects, no other text.
```

**Failure extraction prompt:**
```
Given this task failure, extract gotcha entries as a JSON array.
Each entry must have "type" set to "gotcha", "text", and optionally "source_file".

Rules:
- Focus on what CONFUSED the agent, not the code that was wrong
- Extract edge cases, ambiguities, and patterns that need caution
- Do NOT include the failed code itself
- Keep each entry concise (1-3 sentences)

Failure reason: {failure_log}

Respond with ONLY a JSON array of entry objects, no other text.
```

### Testing Strategy

**Mox mocks:** Use `LLMMock` for controlled LLM responses, `EmbedderMock` for deterministic vectors. No FileSystem mock needed — hygiene doesn't read files directly (it receives execution context).

**Database:** Real SQLite + sqlite-vec via Ecto sandbox (`Familiar.DataCase`). Tests are `async: false` due to sqlite-vec virtual table.

**Test patterns from Stories 2.1/2.2:**
- `deterministic_vector(primary, secondary)` helper for 768-dim vectors
- `setup :verify_on_exit!` for Mox verification
- Clean embedding table in setup: `Repo.query!("DELETE FROM knowledge_entry_embeddings")`
- `Mox.set_mox_global()` for tests using `Task.async_stream` (from 2.2 review)
- Stub `ClockMock` and `FileSystemMock` if search/freshness is exercised indirectly

### Previous Story Intelligence

From Story 2.2:
- `Task.async_stream` requires `Mox.set_mox_global()` in tests — ordered `expect` calls fail with concurrent execution, use `stub` instead
- `replace_embedding/2` now checks delete result before inserting (P5 fix)
- `delete_entry/1` propagates `Repo.delete` result (P4 fix)
- `LocalFileSystem.stat/1` converts mtime to DateTime via `DateTime.from_unix!/1` (P1 critical fix)
- Background tasks via `Task.start` run outside Ecto sandbox — deferred W2

From Story 2.1:
- `store/1` validates content via ContentValidator (FR19) — hygiene entries are LLM-generated prose, should pass
- `store_with_embedding/1` bypasses FR19 — use this for hygiene entries (same justification as init scan)
- `quiet_summary` pattern matching must be specific to avoid shadowing

From Epic 1 retrospective:
- Credo strict: keep functions short, no deep nesting
- Sequential counter-based deterministic vectors prevent birthday paradox collisions

### Project Structure Notes

New files:
```
lib/familiar/knowledge/hygiene.ex              # Post-task hygiene loop
test/familiar/knowledge/hygiene_test.exs       # Hygiene unit tests
```

Modified files:
```
lib/familiar/knowledge/knowledge.ex            # Add hygiene-related public API if needed
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 2, Story 2.3]
- [Source: _bmad-output/planning-artifacts/architecture.md — Post-task hygiene logic, lines 207-210]
- [Source: _bmad-output/planning-artifacts/architecture.md — Knowledge entry types, lines 489-498]
- [Source: _bmad-output/planning-artifacts/architecture.md — Embedding worker pool, line 283]
- [Source: _bmad-output/planning-artifacts/architecture.md — Critical data flow, lines 163-174]
- [Source: _bmad-output/planning-artifacts/prd.md — FR12 post-task knowledge capture]
- [Source: lib/familiar/knowledge/extractor.ex — Extraction patterns, prompt design, valid_entry? whitelist]
- [Source: lib/familiar/knowledge/knowledge.ex — store/1, store_with_embedding/1, search_similar/2, replace_embedding/2]
- [Source: _bmad-output/implementation-artifacts/2-2-context-freshness-validation.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/2-1-knowledge-entry-crud-semantic-search.md — CRUD patterns]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Credo strict found 3 issues after initial implementation: nested too deep in `find_duplicate`, unaliased nested modules in `update_existing`, unsorted alias in test. All resolved by extracting `check_results_for_duplicate/2` helper, adding top-level aliases, and reordering test aliases.

### Completion Notes List

- Created `Familiar.Knowledge.Hygiene` module with `run/2` entry point, `extract_from_success/2`, `extract_from_failure/2`, `store_with_dedup/2`
- Success extraction uses LLM with post-task prompt; produces fact, decision, gotcha, relationship, convention entries
- Failure extraction uses LLM with failure-focused prompt; filters to gotcha-only entries
- Duplicate detection via `Knowledge.search_similar/2` with cosine distance < 0.3 AND same source_file
- Superseding updates existing entry text + re-embeds via `replace_embedding/2`
- Fail-open: LLM unavailability or exceptions produce `{:ok, %{extracted: 0, ...}}` with warning log
- All extracted text passes through `SecretFilter.filter/1`
- Source tagging: all entries use `source: "post_task"`
- DI via opts `:llm` key following established pattern
- 26 hygiene-specific tests covering all ACs
- Full suite: 425 tests, 0 failures, 4 properties. Credo strict: 0 issues.

### Change Log

- 2026-04-02: Implemented Story 2.3 — Post-Task Hygiene Loop (all 6 tasks)

### File List

New files:
- familiar/lib/familiar/knowledge/hygiene.ex
- familiar/test/familiar/knowledge/hygiene_test.exs

Modified files:
- _bmad-output/implementation-artifacts/2-3-post-task-hygiene-loop.md
- _bmad-output/implementation-artifacts/sprint-status.yaml
