# Story 2.1: Knowledge Entry CRUD & Semantic Search

Status: done

## Story

As a user,
I want to search the knowledge store with natural language queries and get semantically relevant results,
So that I can find project context without knowing exact terms or file locations.

## Acceptance Criteria

1. **Given** knowledge entries exist in the store, **When** the user runs `fam search "how does authentication work"`, **Then** entries are returned ranked by semantic similarity, retrieval completes within 2 seconds for 200+ entries (NFR1), and results include entry type, summary, source, and freshness status.

2. **Given** the knowledge store public API (`Familiar.Knowledge`), **When** `search/1`, `fetch_entry/1`, `store/1` are called, **Then** `search/1` returns a ranked list of entries, `fetch_entry/1` returns `{:ok, entry}` or `{:error, {:not_found, details}}`, `store/1` validates the knowledge-not-code rule (FR19) — rejects raw code, accepts prose descriptions, and entries are automatically embedded on creation (FR9).

3. **Given** the system creates knowledge entries, **When** any entry is stored via any path, **Then** the entry contains: text content, embedding vector, type, source, source file references, and timestamps (FR8). The knowledge-not-code rule is enforced — entries are navigational knowledge, not code copies (FR19).

4. **Given** search and CRUD operations are implemented, **When** unit tests run, **Then** semantic search ranking is tested with known embeddings (Mox mock for deterministic vectors), knowledge-not-code validation is tested with positive and negative cases, and all public API functions have near-100% coverage.

## Tasks / Subtasks

- [x] Task 1: Implement `fetch_entry/1` (AC: 2)
  - [x] 1.1 Replace stub in `knowledge.ex` with `Repo.get(Entry, id)` returning `{:ok, entry}` or `{:error, {:not_found, %{id: id}}}`
  - [x] 1.2 Unit tests: found entry, not-found entry, invalid ID (nil)

- [x] Task 2: Implement knowledge-not-code validation (AC: 2, 3)
  - [x] 2.1 Create `Familiar.Knowledge.ContentValidator` module
  - [x] 2.2 Implement `validate_not_code/1` — detect raw code patterns (function defs, module declarations, braces/brackets blocks, import statements) vs prose descriptions
  - [x] 2.3 Return `{:ok, text}` or `{:error, {:knowledge_not_code, %{reason: reason}}}`
  - [x] 2.4 Unit tests: reject raw code (Elixir `defmodule`, JS `function`, Go `func`, Python `def`, Rust `fn`/`impl`), accept prose, accept mixed with inline code references, edge cases (empty, whitespace-only)

- [x] Task 3: Implement `store/1` with validation pipeline (AC: 2, 3)
  - [x] 3.1 Replace stub in `knowledge.ex`: validate content → delegate to `store_with_embedding/1`
  - [x] 3.2 Apply `ContentValidator.validate_not_code/1` before storage
  - [x] 3.3 Unit tests: successful store, code rejection, changeset validation failure, embedding failure propagation

- [x] Task 4: Implement `search/1` wrapping `search_similar/2` (AC: 1, 2)
  - [x] 4.1 Replace stub in `knowledge.ex`: embed query → search sqlite-vec → format results with type, summary, source
  - [x] 4.2 Format results as `[%{id, text, type, source, source_file, distance, inserted_at}]`
  - [x] 4.3 Unit tests: results ranked by distance, empty results, embedding failure

- [x] Task 5: Add CLI `fam search` command (AC: 1)
  - [x] 5.1 Add `run_with_daemon({"search", args, _}, deps)` clause in `main.ex` — call `Knowledge.search/1` with first arg as query
  - [x] 5.2 Add text formatter for "search" — format results as numbered list with type, text excerpt, source
  - [x] 5.3 Add quiet summary: `"results:#{length(results)}"` in output.ex
  - [x] 5.4 Update `help_text/0` with search command
  - [x] 5.5 Unit tests for CLI dispatch, formatting, usage error, error propagation

- [x] Task 6: Expand Entry valid types and sources (AC: 3)
  - [x] 6.1 Add `"fact"` and `"gotcha"` to `@valid_types` in `entry.ex` — existing types remain
  - [x] 6.2 Add `"agent"` and `"user"` to `@valid_sources` — existing sources remain
  - [x] 6.3 Existing entry tests automatically cover new types/sources via `valid_types()` iteration

- [x] Task 7: Comprehensive test coverage (AC: 4)
  - [x] 7.1 Search ranking test: store entries with deterministic vectors, verify ordering by distance
  - [x] 7.2 Knowledge-not-code: 15 tests covering 5 languages, prose, mixed, edge cases
  - [x] 7.3 Full CRUD cycle test: store → fetch → search → verify with new types/sources
  - [x] 7.4 Error paths: not-found, nil ID, validation failures, code rejection, embedding unavailable

### Review Findings

- [x] [Review][Decision] D1: AC1 requires "freshness status" in search results, but freshness validation is Story 2.2. Resolved: defer freshness to Story 2.2 — AC1 is partially satisfied, freshness field will be added when freshness validation exists.
- [x] [Review][Patch] P1: `store/1` text lookup masks missing text — fixed: nil text falls through to changeset validation [knowledge.ex]
- [x] [Review][Patch] P2: `quiet_summary(%{results: results})` too broad — fixed: match `%{results: _, query: _}` [output.ex]
- [x] [Review][Patch] P3: CRLF line endings cause `code_ratio` undercount — fixed: normalize `\r\n` before splitting [content_validator.ex]
- [x] [Review][Patch] P4: `store_with_embedding/1` bypasses FR19 — fixed: documented as internal, `store/1` is public API [knowledge.ex]
- [x] [Review][Patch] P5: `search/1` accepts empty/whitespace query — fixed: empty query returns `{:ok, []}` [knowledge.ex]
- [x] [Review][Patch] P6: ContentValidator threshold boundary untested — fixed: added 59%/60% boundary tests + CRLF test [content_validator_test.exs]
- [x] [Review][Defer] W1: Compensating `Repo.delete` return value ignored in `embed_or_rollback` — pre-existing from Story 1.2
- [x] [Review][Defer] W2: `load_entries_with_distances` TOCTOU nil distance crash if entry deleted between queries — pre-existing from Story 1.2
- [x] [Review][Defer] W3: No 2-second performance test for 200+ entries — deferred to Story 2.7 integration test

## Dev Notes

### Architecture Compliance

**Hexagonal architecture boundary:** This story operates within the Knowledge context. All database access through Ecto Repo. External systems (LLM/Embedder) accessed via existing Mox-backed behaviours.

**Context public API pattern** (from architecture):
- `fetch_*` returns `{:ok, record} | {:error, {:not_found, details}}` — never raise, never return nil
- `list_*` returns a list (empty list when none found)
- Create/update: `{:ok, record} | {:error, {type, details}}`
- Delete: `:ok | {:error, {type, details}}`

**Error convention:** `{:error, {atom_type, map_details}}` everywhere. Relevant types:
- `:not_found` — entry doesn't exist
- `:validation_failed` — changeset errors
- `:knowledge_not_code` — content rejected by FR19 rule
- `:provider_unavailable` — embedding service down
- `:query_failed` — sqlite-vec query error

### Existing Code to Reuse — DO NOT REINVENT

| What | Where | Notes |
|------|-------|-------|
| `store_with_embedding/1` | `knowledge.ex:44-58` | Full insert→embed→store pipeline with compensating deletes. `store/1` should delegate here after validation |
| `search_similar/2` | `knowledge.ex:92-116` | Vector search with limit option. `search/1` should wrap this with result formatting |
| `list_by_type/2` | `knowledge.ex:17-20` | Already implemented |
| `Entry.changeset/2` | `entry.ex:26-33` | Validates types, sources, JSON metadata |
| `embed_or_rollback/1` | `knowledge.ex:60-70` | Compensating transaction — embedding failure deletes entry |
| `insert_embedding/2` | `knowledge.ex:122-134` | 768-dim enforcement |
| CLI dispatch pattern | `main.ex:82-95` | Auto-init then `run_with_daemon` |
| CLI text formatters | `main.ex:257-318` | Pattern match on command name |
| `Output.quiet_summary` | `output.ex:91-98` | Add clause for search results |
| DI pattern | `main.ex:248-255` | `default_deps` map, overridable in tests |

### Knowledge-Not-Code Rule (FR19)

The architecture is explicit: "Entries embed well because they're prose descriptions, not syntax." The knowledge store is "an index card system, not a code mirror."

**What to reject:** Raw code blocks — function definitions, class/module declarations, import/require blocks, syntax-heavy content that would be better read fresh from the filesystem.

**What to accept:** Prose descriptions of code behavior ("The auth module uses JWT tokens with 24h expiry"), convention references ("All controllers follow the single-action pattern"), relationship descriptions ("The User schema belongs_to Organization through team membership"), references that include inline code mentions ("Uses `GenServer.call/2` for synchronous requests").

**Implementation approach:** Pattern detection, not ML. Heuristic: if >60% of lines look like code (start with keywords, contain syntax-heavy patterns), reject. Keep it simple — a regex-based classifier, not a parser.

### CLI Search Command

`fam search "query"` is a **top-level daily action** per UX design. It does NOT need the daemon for database queries — the search goes directly to the local SQLite database. However, it DOES need the Ollama embedder to embed the query. Since the existing `search_similar/2` already handles embedding via `Familiar.Providers.embed/1`, the CLI command can call `Knowledge.search/1` directly.

**But note:** The current `run_with_daemon` pattern expects daemon connectivity. Since `search` only needs the database + Ollama (not the HTTP daemon), consider whether it should be a local command (like `version`) or go through the daemon. Looking at the existing pattern where `conventions` reads directly from `Repo.all(Entry)` via `default_conventions/1`, search should follow the same pattern — read from Repo directly, embed via provider.

**Text output format:**
```
Search results for "authentication" (4 found):

  1. [convention] All API endpoints require Bearer token authentication
     Source: lib/app/router.ex | init_scan

  2. [architecture] JWT token validation middleware with configurable expiry
     Source: lib/app/auth.ex | init_scan

  3. [decision] Session-based auth rejected in favor of stateless JWT
     Source: docs/adr-003.md | init_scan

  4. [relationship] Auth module depends on Config for token signing key
     Source: lib/app/auth.ex | init_scan
```

### Entry Type Expansion

**Current valid types:** `convention`, `file_summary`, `architecture`, `relationship`, `decision`
**Adding:** `fact`, `gotcha`

These new types are used by post-task hygiene (Story 2.3) and manual creation. Init-scan entries use existing types. All types must coexist — do NOT remove or rename existing types.

**Current valid sources:** `init_scan`, `post_task`, `manual`
**Adding:** `agent`, `user`

`agent` is for entries created by task execution agents. `user` is for entries created or edited by the user directly (Story 2.4).

### Testing Strategy

**Mox mocks:** Use existing `Familiar.Providers.LLMMock` and `Familiar.Knowledge.EmbedderMock`. The embedder mock returns deterministic 768-dim vectors — use the sequential counter pattern from Story 1.7 (`:counters` module) for guaranteed unique vectors.

**Database:** Real SQLite + sqlite-vec via Ecto sandbox (`Familiar.DataCase`). Tests are `async: false` due to sqlite-vec virtual table.

**ContentValidator tests:** Pure function, no mocks needed. Test with representative code snippets from multiple languages.

### Previous Story Intelligence

From Epic 1 retrospective (deferred fixes):
- `Entry.validate_json/2` now requires JSON **objects** (not arrays/primitives)
- `Output.quiet_summary` ordering matters — more specific patterns first to avoid shadowing
- Sequential counter-based deterministic vectors prevent birthday paradox collisions
- Compensating transaction pattern (delete on embed failure) is proven and tested
- Credo strict: keep functions short, no deep nesting, avoid `length/1` comparisons (use `!= []` or pattern match)
- `@moduletag :tmp_dir` only needed for filesystem tests — CRUD tests don't need it

From Story 1.7:
- Shell mock stubs needed if any test path triggers `CommandValidator.validate/2`
- `Mox.stub/3` for variable call counts, `Mox.expect/3` for exact counts
- `DataCase` + `MockCase` combo for integration tests

### Project Structure Notes

New files:
```
lib/familiar/knowledge/content_validator.ex    # Knowledge-not-code rule
test/familiar/knowledge/content_validator_test.exs
test/familiar/knowledge/knowledge_test.exs     # CRUD + search tests (or extend existing)
```

Modified files:
```
lib/familiar/knowledge/knowledge.ex    # Replace stubs with implementations
lib/familiar/knowledge/entry.ex        # Expand valid types/sources
lib/familiar/cli/main.ex              # Add search command
lib/familiar/cli/output.ex            # Add search quiet summary
test/familiar/knowledge/entry_test.exs # New type/source tests
test/familiar/cli/main_test.exs       # Search command tests
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 2, Story 2.1]
- [Source: _bmad-output/planning-artifacts/architecture.md — Knowledge Context Public API, CRUD Operations Pattern, Knowledge Entry Content Strategy, Secret Detection]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — fam search as daily top-level action, text output format]
- [Source: lib/familiar/knowledge/knowledge.ex — Existing stubs and store_with_embedding/search_similar implementations]
- [Source: lib/familiar/knowledge/entry.ex — Current schema with 5 types, 3 sources, JSON metadata validation]
- [Source: lib/familiar/cli/main.ex — CLI dispatch pattern, run_with_daemon, text formatters]
- [Source: lib/familiar/cli/output.ex — quiet_summary ordering pattern]
- [Source: _bmad-output/implementation-artifacts/1-7-foundation-integration-test.md — Deterministic vector pattern, compensating transaction pattern]
- [Source: _bmad-output/implementation-artifacts/epic-1-retro-2026-04-02.md — Deferred fix learnings]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Implemented `fetch_entry/1` with nil guard clause (Repo.get raises on nil)
- Created `ContentValidator` with regex-based code detection across 5 languages (Elixir, JS, Go, Python, Rust) using 60% code-line threshold
- Implemented `store/1` as thin validation layer over existing `store_with_embedding/1`
- Implemented `search/1` wrapping `search_similar/2` with flat result maps
- Added CLI `fam search` command with text formatter, quiet summary, usage error handling
- Updated test deps helper to merge extra keys (search_fn) for DI testing
- Expanded Entry types (added fact, gotcha) and sources (added agent, user)
- Full CRUD cycle test validates store → fetch → search with new types/sources
- Fixed 3 Credo strict issues: alias ordering, large number formatting
- Final: 373 tests + 4 properties, 0 failures. Credo strict: 0 issues

### File List

New files:
- familiar/lib/familiar/knowledge/content_validator.ex
- familiar/test/familiar/knowledge/content_validator_test.exs
- familiar/test/familiar/knowledge/knowledge_test.exs

Modified files:
- familiar/lib/familiar/knowledge/knowledge.ex
- familiar/lib/familiar/knowledge/entry.ex
- familiar/lib/familiar/cli/main.ex
- familiar/lib/familiar/cli/output.ex
- familiar/test/familiar/cli/main_test.exs
