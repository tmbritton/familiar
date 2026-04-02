# Story 3.2: Spec Generation & Verification

Status: done

## Story

As a user,
I want a thorough feature specification with verified assumptions and cited sources,
So that I can trust the spec before approving execution.

## Acceptance Criteria

### AC1: Verified Spec Generation
**Given** the user ends the planning conversation (explicitly or via `fam plan` generating the spec)
**When** the system generates a specification
**Then** the spec is a markdown file stored in the project directory
**And** claims verified against the knowledge store and filesystem are marked ✓
**And** unverified assumptions are marked ⚠ and explicitly labeled
**And** context sources are cited inline (e.g., "✓ users table has email column — verified in db/migrations/001_init.sql")
**And** conventions are annotated (e.g., "Following existing pattern: handler/song.go")

### AC2: Tool-Call-Based Verification
**Given** verification runs during spec generation
**When** a claim references a file
**Then** verification is derived from the tool call log — only actual file reads count as verification
**And** the LLM cannot self-report verification status
**And** claims citing files NOT in the tool call log are marked ⚠ unverified

### AC3: Freshness Gate
**Given** the spec references files
**When** freshness is checked
**Then** the same freshness gate as task dispatch runs — stale files trigger re-scan before verification

### AC4: Test Coverage
**Given** spec generation is implemented
**When** unit tests run
**Then** verification mark logic is tested against known tool call logs
**And** spec markdown generation is tested for correct formatting
**And** 100% coverage on `Planning.Verification` (critical module)
**And** property test: every ✓ mark has a corresponding tool call in the log; no tool call is missed

### AC5: Project-Specific Awareness
**Given** a test project with known conventions and knowledge entries
**When** a spec is generated for a well-defined feature request
**Then** the spec demonstrates project-specific awareness (references actual conventions, files, and patterns — not generic output)

## Tasks / Subtasks

- [x] Task 1: Spec Ecto schema and migration (AC: #1)
  - [x] Create migration `create_planning_specs` with columns: id, session_id (FK), title, body, status, metadata, file_path, timestamps
  - [x] Create `Planning.Spec` Ecto schema with changeset validation
  - [x] Tests: schema changeset validation, persistence, FK constraint (10 tests)

- [x] Task 2: Verification module — pure function (AC: #2, #4)
  - [x] Create `Planning.Verification` module
  - [x] `verify_claims/2` — cross-references claims against tool call log
  - [x] `extract_claims/1` — parses inline file references from spec markdown
  - [x] `annotate_spec/2` — injects ✓/⚠ marks with source citations
  - [x] `build_metadata/1` — returns verified/unverified/total counts
  - [x] 100% coverage with 4 property tests + 20 unit tests
  - [x] Property: every ✓ has matching tool call; empty log = all ⚠; no file_refs = always ⚠

- [x] Task 3: Spec generation via LLM (AC: #1, #5)
  - [x] Create `Planning.SpecGenerator` module with tool dispatch loop
  - [x] Tool definitions: `file_read` (FileSystem.read) and `knowledge_search` (Knowledge.search)
  - [x] Tool dispatch: execute tool_calls, inject results as tool messages, re-call LLM (max 10 rounds)
  - [x] SecretFilter applied to tool results and spec body
  - [x] Tests: 9 tests with stub providers (with/without tools), file dispatch, knowledge dispatch

- [x] Task 4: Freshness integration (AC: #3)
  - [x] Stat-check file paths from tool call log via FileSystem behaviour
  - [x] Stale files: mark as ⚠ with "(stale)" annotation
  - [x] Deleted files: mark as ⚠ with "(file not found)" annotation
  - [x] Tests: StubFileSystem returns :enoent for lib/auth.ex, fresh for db/migrations

- [x] Task 5: Spec file persistence and CLI output (AC: #1)
  - [x] Write to `.familiar/specs/{session_id}-{slug}.md` via FileSystem.write
  - [x] YAML frontmatter: title, session_id, status, generated_at, verified, unverified
  - [x] Session status updated to "completed"
  - [x] Metadata line in body: "Generated {date} · {n} verified · {m} unverified"
  - [x] Tests: verify persistence, session completion, body format

- [x] Task 6: Engine integration — wire spec generation (AC: #1, #2)
  - [x] `Engine.generate_spec/2` delegates to SpecGenerator.generate
  - [x] `Engine.get_spec/1` fetches spec by ID
  - [x] `Planning.generate_spec/2` and `Planning.get_spec/1` delegation
  - [x] Tests: generate_spec from session, get_spec, error cases (4 tests)

- [x] Task 7: Planning public API and CLI updates (AC: #1)
  - [x] `fam spec <id>` CLI command with text formatter
  - [x] Help text updated
  - [x] Tests: CLI parse_args, spec display, error cases (4 tests)

## Dev Notes

### Review Findings

- [x] [Review][Decision] D1: generate_spec CLI — deferred, triggered via approval flow (Story 3.4)
- [x] [Review][Decision] D2: Conventions count added to build_metadata, frontmatter, and meta line
- [x] [Review][Patch] P1: Path traversal validated — rejects absolute paths and `..` components [spec_generator.ex]
- [x] [Review][Patch] P2: Session guard — validate_active in Engine + validate_specifiable in SpecGenerator [engine.ex, spec_generator.ex]
- [x] [Review][Patch] P3: complete_session now logs warnings on failure [spec_generator.ex]
- [x] [Review][Patch] P4: Added 5th property test — every file_read tool call referenced by claims appears verified [verification_test.exs]
- [x] [Review][Patch] P5: Freshness test added — verifies ⚠ downgrade for deleted files, ✓ for fresh [spec_generator_test.exs]
- [x] [Review][Patch] P6: System prompt included in messages via PromptAssembly.assemble (was already present — `_system` discarded cosmetically but messages list contains it)
- [x] [Review][Patch] P7: load_messages now includes tool_calls from assistant messages via message_to_map/1 [spec_generator.ex]
- [x] [Review][Patch] P8: SecretFilter applied to knowledge_search results [spec_generator.ex]
- [x] [Review][Patch] P9: YAML title escaped — quotes and newlines sanitized [spec_generator.ex]
- [x] [Review][Patch] P10: Removed `e.text` fallback — uses only `e[:text]` consistently [spec_generator.ex]
- [x] [Review][Patch] P11: Unique index on planning_specs.session_id + unique_constraint in changeset [migration, spec.ex]
- [x] [Review][Patch] P12: Text truncation raised to 2000 chars with truncation indicator [cli/main.ex]
- [x] [Review][Patch] P13: tool_call_id uses index fallback for uniqueness [spec_generator.ex]
- [x] [Review][Patch] P14: Path normalization — strip `./` prefix in both claims and tool log [verification.ex]
- [x] [Review][Patch] P15: List accumulation uses prepend + reverse pattern [spec_generator.ex]
- [x] [Review][Patch] P16: slugify falls back to "untitled" for empty slugs [spec_generator.ex]
- [x] [Review][Patch] P17: Proper frontmatter boundary tracking — skip lines between `---` delimiters [verification.ex]
- [x] [Review][Patch] P18: Tool loop exhaustion test added [spec_generator_test.exs]
- [x] [Review][Defer] W1: StubFileSystem duplicated across 3 test files — refactor to shared module later [test/support/]

### Architecture Constraints

- **Hexagonal architecture**: All LLM calls through `Providers.chat/2`, file reads through `Familiar.System.FileSystem` behaviour, knowledge queries through `Knowledge.search/1` or `Librarian.query/2`.
- **Verification is tool-call-based**: The LLM cannot self-report verification. Only actual tool calls (file reads, context queries) logged during spec generation count as verification evidence. This is the architectural defense against hallucinated ✓ marks.
- **One verification log, two consumers**: The tool call log feeds both the streaming reasoning trail (Story 3.3) and the spec's inline verification marks. Story 3.2 builds the log and consumes it for marks; Story 3.3 will consume it for the trail.
- **Error tuples**: All public functions return `{:ok, result}` or `{:error, {atom, map}}`.
- **SecretFilter**: Applied to all persisted text (spec body, tool results).

### Existing Code to Reuse

| Module | API | Use For |
|--------|-----|---------|
| `Planning.Engine` | `start_plan/2`, `respond/3`, `call_llm/2` | Conversation flow; extend with `generate_spec/2` |
| `Planning.Session` | Ecto schema with context column | Store spec metadata on session |
| `Planning.Message` | Ecto schema with tool_calls column | Tool call log is already persisted per message |
| `Providers.chat/2` | `chat(messages, opts)` → `{:ok, map}` | LLM calls for spec generation |
| `Knowledge.search/1` | `search(query)` → `{:ok, [map]}` | Tool dispatch for knowledge_search calls |
| `Knowledge.Freshness` | `validate_entries/2` → freshness map | Freshness gate for referenced entries |
| `System.FileSystem` | `.read/1`, `.stat/1` | Tool dispatch for file_read calls |
| `Knowledge.SecretFilter` | `filter/1` → filtered string | Filter secrets from spec text and tool results |
| `Familiar.Repo` | Ecto repo with SQLite | All DB operations |

### Tool Dispatch Design

This is the **key new capability** in this story (deferred from Story 3.1 as review finding D1).

During spec generation, the LLM is given tool definitions:
- `file_read(path)` — reads a file from the project directory
- `knowledge_search(query)` — searches the knowledge store

When the LLM returns a response with `tool_calls`, the Engine must:
1. Execute each tool call (via FileSystem.read or Knowledge.search)
2. Construct a `tool` role message with the result
3. Re-call the LLM with the tool result appended to messages
4. Repeat until the LLM returns a final response with no tool_calls
5. Log all tool calls with timestamps for the verification module

The tool call log is the **single source of truth** for verification marks.

### Verification Module Design

`Planning.Verification` is the **critical pure-function module** (100% coverage required).

**Input:** Raw spec markdown + tool call log (list of `%{type, path, timestamp}`)
**Output:** Annotated spec markdown with ✓/⚠ marks + metadata counts

The flow:
1. `extract_claims/1` — parse spec markdown for inline file references (regex for file paths, table names, migration references)
2. `verify_claims/2` — cross-reference claims against tool call log; claims with matching file_read entries → ✓, others → ⚠
3. `annotate_spec/2` — inject ✓/⚠ marks and source citations into the markdown

**Property tests:**
- For any spec text and tool call log: every ✓ claim has a matching tool call entry
- For any spec text and empty tool call log: all claims are ⚠
- For any tool call log: no tool call entry is unreferenced in the output metadata

### Spec Markdown Format

```markdown
---
title: "Add User Accounts"
session_id: 42
status: draft
generated_at: 2026-04-02T17:00:00Z
verified: 5
unverified: 2
conventions: 3
---

# Add User Accounts

Generated 2026-04-02 · 5 verified · 2 unverified · 3 conventions applied

## Assumptions

✓ Users table has email and hashed_password columns — verified in db/migrations/001_init.sql
✓ Auth middleware validates session tokens — verified in lib/auth.ex
⚠ Rate limiting for login attempts — not verified (no existing implementation found)

## Conventions Applied

Following existing pattern: handler/song.go → handler/user.go
Following existing pattern: db/song_repo.go → db/user_repo.go
Following existing naming: templates in templates/user/

## Implementation Plan

1. Create user schema and migration
2. Add authentication handler
3. ...
```

### Previous Story Intelligence

**From Story 3.1 review findings:**
- **D1 (deferred to this story):** Tool calls declared but never dispatched. `@tool_definitions` in Engine passes `knowledge_search` tool to LLM, but tool_call responses are stored without execution. This story implements the dispatch loop.
- **Engine architecture:** `call_llm/2` loads messages from DB, assembles via PromptAssembly, calls `Providers.chat` with `tools: @tool_definitions`. The response's `tool_calls` are already persisted in `planning_messages.tool_calls` as JSON.
- **Context persistence:** Session now has a `context` column storing the Librarian summary. This is reloaded on every `call_llm/2` via `PromptAssembly.assemble(session.context, history)`.
- **SecretFilter:** Applied in `insert_message/4` to all persisted content. Apply to spec body and tool results too.
- **Test baseline:** 611 tests + 8 properties, 0 failures. Credo strict: 0 issues. Do not regress.

### Testing Standards

- **Mox for all behaviours**: LLM, FileSystem, Shell, Notifications, Clock, Embedder
- **Ecto sandbox**: `use Familiar.DataCase, async: true` where possible
- **Property tests**: Required for `Planning.Verification` — StreamData generators for spec text, file references, and tool call logs
- **100% coverage**: `Planning.Verification` (critical module)
- **Near-100% coverage**: SpecGenerator, spec persistence
- **Integration test**: Deferred to Story 3.7

### Project Structure Notes

New files to create:
```
familiar/lib/familiar/planning/
├── verification.ex          # Pure function: tool call log → verification marks
├── spec_generator.ex        # LLM-driven spec generation with tool dispatch
└── spec.ex                  # Ecto schema for planning_specs

familiar/priv/repo/migrations/
└── *_create_planning_specs.exs

familiar/test/familiar/planning/
├── verification_test.exs    # 100% coverage + property tests
├── spec_generator_test.exs
└── spec_test.exs
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 3, Story 3.2]
- [Source: _bmad-output/planning-artifacts/architecture.md — Planning context, verification patterns]
- [Source: _bmad-output/planning-artifacts/prd.md — FR23, FR24, FR24b]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Spec view, verification marks]
- [Source: _bmad-output/implementation-artifacts/3-1-planning-conversation-engine.md — D1 deferred item, Engine architecture]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Task 1: Spec schema + migration with FK, status validation, JSON metadata. 10 tests.
- Task 2: Verification pure function — extract_claims parses file refs from markdown, verify_claims cross-references tool call log, annotate_spec injects ✓/⚠ marks. 20 tests + 4 property tests (100% coverage).
- Task 3: SpecGenerator with tool dispatch loop — LLM calls with file_read/knowledge_search tools, dispatches via FileSystem/Knowledge behaviours, injects results, continues until final response. SecretFilter on all outputs. 9 tests.
- Task 4: Freshness integration — stat-checks tool call log file paths, downgrades verified claims to ⚠ when files are stale/deleted. Integrated into verify_with_freshness pipeline.
- Task 5: Spec file persistence with YAML frontmatter, metadata line, session completion.
- Task 6: Engine.generate_spec/2 and get_spec/1 wired up with Planning context delegation.
- Task 7: `fam spec <id>` CLI command with text formatter showing title, status, file path, body preview.
- Total: 48 new tests + 4 new property tests. Full suite: 659 tests + 12 properties, 0 failures. Credo strict: 0 issues.

### Change Log

- 2026-04-02: Story 3.2 implemented — Spec Generation & Verification with tool dispatch and freshness integration

### File List

- familiar/priv/repo/migrations/20260402200002_create_planning_specs.exs (new)
- familiar/lib/familiar/planning/spec.ex (new)
- familiar/lib/familiar/planning/verification.ex (new)
- familiar/lib/familiar/planning/spec_generator.ex (new)
- familiar/lib/familiar/planning/engine.ex (modified — added generate_spec/2, get_spec/1)
- familiar/lib/familiar/planning/planning.ex (modified — added generate_spec/2, get_spec/1 delegation)
- familiar/lib/familiar/cli/main.ex (modified — added fam spec command, text formatter)
- familiar/test/familiar/planning/spec_test.exs (new)
- familiar/test/familiar/planning/verification_test.exs (new)
- familiar/test/familiar/planning/spec_generator_test.exs (new)
- familiar/test/familiar/planning/engine_test.exs (modified — added generate_spec/get_spec tests)
- familiar/test/familiar/planning/planning_test.exs (modified — updated get_spec, added generate_spec test)
- familiar/test/familiar/cli/main_test.exs (modified — added spec command tests)
