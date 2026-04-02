# Story 1.7: Foundation Integration Test

Status: done

## Story

As a developer,
I want an integration test that validates the full init pipeline end-to-end,
So that I can prove the foundational infrastructure works as a coherent system.

## Acceptance Criteria

1. **Given** the full foundation is built (SQLite + sqlite-vec, provider adapters, file system, knowledge store), **When** the integration test runs, **Then** the golden path is validated: scan project files → classify (index/skip) → extract knowledge via mocked LLM → embed via mocked Ollama → store in real SQLite with sqlite-vec → retrieve by semantic similarity. The test uses real SQLite via Ecto sandbox (not mocked) and sqlite-vec vector operations. External systems (LLM, Embedder) are mocked via Mox with scripted responses. The full pipeline completes without error and retrieval returns relevant entries.

2. **Given** the integration test runs against a project fixture, **When** the fixture contains 100+ files, **Then** minimum scale is validated per NFR14 (100+ source files, 200+ context entries). The scan respects `max_files` and `large_project_threshold` settings. Prioritization correctly ranks source files above docs.

3. **Given** failure scenarios are tested, **When** the integration test exercises error paths, **Then** Ctrl+C during init leaves no `.familiar/` directory (atomic rollback via `run_with_cleanup/2`). Ollama unavailable during init produces a clear error and clean exit. Corrupt/invalid files are skipped gracefully without halting the pipeline.

4. **Given** the integration test exercises retrieval, **When** entries have been stored with embeddings, **Then** `Knowledge.search_similar/1` returns entries ranked by cosine distance. Semantically related queries return relevant entries (verified by checking returned entry text/type matches expected). Vector dimension validation (768-dim) is enforced.

## Tasks / Subtasks

- [x] Task 1: Create 100+ file project fixture (AC: 2)
  - [x] 1.1 Create `test/support/fixtures/` directory with a realistic multi-file Elixir project structure
  - [x] 1.2 Generate 100+ files programmatically in test setup: `lib/` source files (60+), `test/` files (20+), config files (5+), docs (10+), plus skip targets (`_build/`, `deps/`, `.git/`)
  - [x] 1.3 Include variety: modules with different patterns (GenServer, Supervisor, schema, controller, context, etc.) to produce diverse knowledge entries

- [x] Task 2: Golden path integration test (AC: 1, 4)
  - [x] 2.1 Create `test/familiar/knowledge/foundation_integration_test.exs`
  - [x] 2.2 Use `Familiar.DataCase` (real Ecto sandbox) + `Familiar.MockCase` (Mox for LLM/Embedder)
  - [x] 2.3 Mock LLM to return scripted JSON responses with valid entry types (`file_summary`, `convention`, `architecture`, `relationship`, `decision`)
  - [x] 2.4 Mock Embedder to return deterministic 768-dim vectors — use distinct vectors for different content so similarity search produces meaningful ordering
  - [x] 2.5 Run `InitScanner.run/2` against the 100+ file fixture
  - [x] 2.6 Assert: `summary.files_scanned >= 100`, `summary.entries_created >= 1`, `summary.conventions_discovered >= 1`
  - [x] 2.7 Verify entries persisted in real SQLite: `Repo.all(Entry)` returns stored entries with correct types and sources
  - [x] 2.8 Verify vector search works: call `Knowledge.search_similar/1` with a query, assert results returned with distance values, assert ordering is by ascending distance

- [x] Task 3: Scale and prioritization test (AC: 2)
  - [x] 3.1 Test with 500+ files (above `@large_project_threshold`) to trigger prioritization
  - [x] 3.2 Assert `max_files` is respected (no more than 200 files processed)
  - [x] 3.3 Assert `deferred > 0` for large projects
  - [x] 3.4 Assert source files (`.ex`) are prioritized over docs (`.md`) in the selected files

- [x] Task 4: Error path tests (AC: 3)
  - [x] 4.1 Test `run_with_cleanup/2`: function returning error → `.familiar/` directory cleaned up
  - [x] 4.2 Test `run_with_cleanup/2`: function raising exception → `.familiar/` directory cleaned up, error returned
  - [x] 4.3 Test LLM unavailable: mock LLM returns `{:error, {:provider_unavailable, ...}}` → pipeline continues with structural conventions, summary includes `extraction_warnings`
  - [x] 4.4 Test corrupt/unreadable files: create files with `0o000` permissions → skipped gracefully, other files still processed
  - [x] 4.5 Test embedding failure: mock Embedder returns error for some entries → entries that fail embedding are rolled back (compensating delete), others succeed

- [x] Task 5: Retrieval verification test (AC: 4)
  - [x] 5.1 Store entries with distinct embedding vectors (e.g., entry A gets vector [1,0,0,...], entry B gets vector [0,1,0,...])
  - [x] 5.2 Search with query vector close to entry A → entry A returned first
  - [x] 5.3 Verify 768-dim enforcement: attempt to store entry with wrong dimension vector → `{:error, {:storage_failed, %{reason: :dimension_mismatch, ...}}}`
  - [x] 5.4 Verify entry fields populated correctly: text, type, source, source_file, metadata, timestamps

### Review Findings

- [x] [Review][Decision] D1: AC3 contradiction — LLM unavailable test asserts `{:ok, summary}` but AC3 says "produces a clear error and clean exit." Resolved: AC wording is imprecise; graceful degradation with warnings is the correct behavior per architecture. Test is correct.
- [x] [Review][Patch] P1: No assertion that `knowledge_entry_embeddings` table is populated — added `Repo.query("SELECT count(*) FROM knowledge_entry_embeddings")` assertion after pipeline completes [foundation_integration_test.exs]
- [x] [Review][Patch] P2: `stub_embedder_deterministic` hash collisions weaken ordering assertion — replaced hash-based indexing with sequential counter to guarantee unique vectors per entry [foundation_integration_test.exs:200-207]
- [x] [Review][Patch] P3: Scale test missing lower-bound assertion — added `assert summary.files_scanned >= 100` to validate NFR14 minimum scale [foundation_integration_test.exs]
- [x] [Review][Patch] P4: `search_similar` ordering test doesn't verify returned entry text/type per AC4 — added `first.entry.text =~ "authentication"` and `second.entry.text =~ "database"` [foundation_integration_test.exs]
- [x] [Review][Defer] W1: No test for SIGINT/signal cleanup path — AC3 says "Ctrl+C during init leaves no `.familiar/`" but production code only traps `:sigterm`/`:sigquit`, not `:sigint`. Signal tests are complex (require spawning processes). Deferred, pre-existing design gap
- [x] [Review][Defer] W2: Root-sensitive `chmod 0o000` test silently passes as false positive when run as root in CI/Docker containers. Deferred, common CI issue with no clean fix
- [x] [Review][Defer] W3: No idempotent re-init test (running init twice). Deferred, out of story scope
- [x] [Review][Defer] W4: Corrupt file test only covers permission-denied, not corrupt file content (binary garbage, null bytes). Deferred, minor
- [x] [Review][Defer] W5: No test for non-existent project_dir passed to scan_files. Deferred, edge case
- [x] [Review][Defer] W6: No test for `search_similar` `limit` option behavior. Deferred, out of scope

## Dev Notes

### Architecture Compliance

**This is an integration test, not a unit test.** Key distinction from existing `init_scanner_test.exs`:
- Existing tests: mock LLM/Embedder, test pipeline flow, small fixture (1-5 files)
- This test: mock LLM/Embedder (external systems), but use **real SQLite + sqlite-vec** (internal systems), test full pipeline including retrieval, large fixture (100+ files)

**Hexagonal architecture test boundary:**
- **Real:** SQLite database (Ecto sandbox), sqlite-vec vector operations, FileClassifier, ConventionDiscoverer (structural), InitScanner orchestration, Knowledge.store_with_embedding, Knowledge.search_similar
- **Mocked via Mox:** LLM (Familiar.Providers.LLMMock), Embedder (Familiar.Knowledge.EmbedderMock)
- **Real filesystem:** Use `@moduletag :tmp_dir` for fixture creation — real files on disk, real `LocalFileSystem` for walking

### Test File Location

```
test/familiar/knowledge/foundation_integration_test.exs
```

This follows existing test structure where `init_scanner_test.exs` already lives.

### Fixture Generation Strategy

Generate files programmatically in `setup` using the existing `create_file/3` helper pattern from `init_scanner_test.exs`. Do NOT create static fixture files — generate them at test time for isolation.

```elixir
# Example: generate 60+ source files
for i <- 1..60 do
  create_file(tmp_dir, "lib/app/mod#{i}.ex", """
  defmodule App.Mod#{i} do
    @moduledoc "Module #{i} for testing"
    def run, do: :ok
  end
  """)
end
```

Include realistic variety:
- `lib/app/` — application modules
- `lib/app/workers/` — GenServer-style modules
- `test/app/` — test files
- `config/` — config files
- `docs/` — markdown docs
- `_build/`, `deps/`, `.git/` — skip targets (verify they're excluded)

### Mox Scripting Strategy

**LLM Mock:** Return valid JSON arrays matching the extraction prompt format. Use `Mox.stub/3` (not `expect`) since the call count depends on file count.

```elixir
Mox.stub(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
  prompt = hd(messages).content

  if prompt =~ "conventions" do
    # Convention discovery LLM response
    {:ok, %{content: Jason.encode!([
      %{"type" => "convention", "text" => "Follows module naming convention",
        "evidence_count" => 5, "evidence_total" => 10}
    ])}}
  else
    # File extraction response — extract source_file from prompt
    file = Regex.run(~r/File: (.+)\n/, prompt, capture: :all_but_first)
    source = if file, do: hd(file), else: "unknown"
    {:ok, %{content: Jason.encode!([
      %{"type" => "file_summary", "text" => "Module providing functionality",
        "source_file" => source}
    ])}}
  end
end)
```

**Embedder Mock:** Return deterministic 768-dim vectors. For meaningful similarity search testing, use vectors that encode content identity:

```elixir
Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
  # Generate deterministic vector from text hash for consistent ordering
  hash = :erlang.phash2(text, 1000)
  base = List.duplicate(0.0, 768)
  # Set a few dimensions based on hash for differentiation
  vector = List.replace_at(base, rem(hash, 768), 1.0)
  {:ok, vector}
end)
```

### Existing Code to Reuse

| What | Where | How |
|------|-------|-----|
| `InitScanner.run/2` | `lib/familiar/knowledge/init_scanner.ex` | Full pipeline entry point |
| `InitScanner.run_with_cleanup/2` | Same file | Atomic cleanup wrapper |
| `Knowledge.store_with_embedding/1` | `lib/familiar/knowledge/knowledge.ex` | Insert → embed → store vector |
| `Knowledge.search_similar/1` | Same file | Vector similarity search |
| `Entry` schema | `lib/familiar/knowledge/entry.ex` | Verify persisted entries |
| `FileClassifier.classify/1` | `lib/familiar/knowledge/file_classifier.ex` | Index/skip classification |
| `DataCase` | `test/support/data_case.ex` | Ecto sandbox setup |
| `MockCase` | `test/support/mock_case.ex` | Mox verify_on_exit |
| `LocalFileSystem` | `lib/familiar/system/local_file_system.ex` | Real filesystem for walking |
| `create_file/3` pattern | `init_scanner_test.exs` | File creation helper |

**Do NOT create:**
- New behaviours or ports — this is a test, not production code
- New test support modules (unless a fixture generator is truly needed for reuse)
- Static fixture files — generate programmatically
- New Mox mock definitions — all 6 already exist

### Error Convention

All errors follow `{:error, {atom_type, map_details}}`:
- `:provider_unavailable` — LLM/Embedder down (recoverable)
- `:storage_failed` — SQLite write failure
- `:init_failed` — Init pipeline failure (from run_with_cleanup)
- `:validation_failed` — Ecto changeset error

### Test Tagging

This test should run with default `mix test` (no special tags needed) since it uses Ecto sandbox + Mox — fast and deterministic. It does NOT require real Ollama.

Mark test as `async: false` since it interacts with filesystem and application env. Use `@moduletag :tmp_dir` for ExUnit's tmp_dir feature.

### sqlite-vec Vector Search

The vector search uses raw SQL through `Repo.query/2`:
```sql
SELECT entry_id, distance
FROM knowledge_entry_embeddings
WHERE embedding MATCH ?
ORDER BY distance
LIMIT ?
```

Vectors are stored as JSON-encoded float arrays. The `knowledge_entry_embeddings` virtual table is created by the migration using sqlite-vec. The Repo loads the sqlite-vec extension in `init/2`.

For deterministic search results, use vectors where cosine distance is predictable:
- Entry "auth module" → vector with `[1.0, 0.0, 0.0, ...]` (dimension 0 hot)
- Entry "database helper" → vector with `[0.0, 1.0, 0.0, ...]` (dimension 1 hot)
- Query "authentication" → vector with `[0.9, 0.1, 0.0, ...]` → should return auth entry first

### Previous Story Learnings

From Story 1.6:
- **String keys for TOML** — TOML keys are strings, not atoms. Config generator tested for valid TOML output
- **Function injection** — deps map pattern in main.ex for injectable dependencies
- **Credo strict** — keep functions short, extract helpers
- **`@moduletag :tmp_dir`** — ExUnit creates/cleans tmp directory per test module

From Stories 1.4/1.5:
- **Error convention** — `{:error, {atom_type, map_details}}` everywhere
- **DefaultFiles.install pattern** — check `File.exists?` before writing
- **Mox.stub vs Mox.expect** — use `stub` when call count is variable, `expect` when exact count matters
- **Concurrent embedding** — `Task.async_stream` with configurable concurrency

### Project Structure Notes

Single new file:
```
test/familiar/knowledge/foundation_integration_test.exs
```

No modifications to existing production code. This is a test-only story.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 1, Story 1.7]
- [Source: _bmad-output/planning-artifacts/architecture.md — Testing Architecture section]
- [Source: _bmad-output/planning-artifacts/prd.md — NFR14: 100+ files, 200+ entries minimum scale]
- [Source: lib/familiar/knowledge/init_scanner.ex — Full pipeline: scan → extract → embed → store]
- [Source: lib/familiar/knowledge/knowledge.ex — store_with_embedding/1, search_similar/1]
- [Source: lib/familiar/knowledge/entry.ex — Schema with 5 types, 3 sources]
- [Source: test/familiar/knowledge/init_scanner_test.exs — Existing test patterns, create_file helper]
- [Source: test/support/mocks.ex — 6 Mox mock definitions]
- [Source: test/support/data_case.ex — Ecto sandbox setup]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Created `foundation_integration_test.exs` with 11 tests covering all 5 tasks and 4 acceptance criteria
- **Golden path test:** Full pipeline scan → classify → extract → embed → store → retrieve with 110-file programmatic fixture, real SQLite + sqlite-vec, mocked LLM/Embedder/Shell
- **Fixture generation:** `generate_fixture/2` creates 110 files (66 source, 22 test, 11 docs, 11 config) with 5 varied patterns (GenServer, Schema, Context, Controller, Supervisor) plus skip targets (_build/, deps/, .git/)
- **Scale test:** 510-file fixture triggers prioritization, verifies max_files=200 respected, deferred>0, source files prioritized over docs
- **Error paths:** run_with_cleanup atomic rollback on error/exception, LLM unavailable continues with structural conventions, corrupt files skipped gracefully, embedding failure triggers compensating delete (no orphan entries)
- **Retrieval verification:** Distinct one-hot vectors for auth/db entries, query vector closest to auth returns auth first, 768-dim enforcement rejects 512-dim vectors with dimension_mismatch error, entry field validation
- Shell mock stub needed for CommandValidator (detects mix.exs → runs shell probe commands)
- Fixed 3 Credo issues: extracted nested function body into helpers, replaced `length/1 > 0` with `!= []`
- Final: 338 tests + 4 properties, 0 failures. Credo strict: 0 issues

### File List

New files:
- test/familiar/knowledge/foundation_integration_test.exs
