# Story 3.4: Spec Review & Approval (CLI)

Status: done

## Story

As a user,
I want to review and approve the generated spec via CLI or $EDITOR,
So that I can evaluate, approve, edit, or reject it before execution begins.

## Acceptance Criteria

### AC1: Spec Summary & Approval Prompt
**Given** a spec has been generated
**When** `fam generate-spec` completes spec generation (FR25)
**Then** the CLI displays a summary: verification counts, convention count, unverified assumptions
**And** the user is prompted to approve, edit, or reject

### AC2: Editor Integration
**Given** the user wants to review the full spec
**When** `fam spec edit <id>` is used or the approval prompt offers edit
**Then** the spec opens in `$EDITOR` for review
**And** on editor close, the user is prompted: approve (a), re-edit (e), or reject (r)

### AC3: Stat-Check on Approve
**Given** the user edited the spec externally
**When** the user returns to approve via CLI
**Then** the system stat-checks the spec file — if modified since generation, it re-reads and confirms the user wants to approve the edited version

### AC4: Spec Status Transitions
**Given** the user approves the spec
**When** approval is confirmed
**Then** the spec is marked as approved (frontmatter status updated, DB status updated)
**And** rejection returns the spec to draft status (or marks rejected)

### AC5: Test Coverage
**Given** spec review is implemented
**When** unit tests run
**Then** CLI approval flow, stat-check-on-approve, and editor integration are tested
**And** near-100% coverage on spec review logic

## Tasks / Subtasks

- [x] Task 1: SpecReview module — approval, rejection, stat-check (AC: #3, #4)
  - [x] Create `Planning.SpecReview` module
  - [x] `approve/2` — loads spec, stat-checks file, updates status to "approved" in DB and frontmatter
  - [x] `reject/2` — updates status to "rejected" in DB and frontmatter
  - [x] `stat_check/1` — compares file mtime against spec `updated_at` to detect external edits
  - [x] `reload_if_modified/1` — re-reads spec file, updates DB body if file was modified
  - [x] Frontmatter update: read file, replace `status: draft` with `status: approved`/`status: rejected`, write back
  - [x] DI: `file_system` opt for testability
  - [x] Tests: approve happy path, reject happy path, stat-check detects modification, stat-check when unmodified, frontmatter update (10 tests)

- [x] Task 2: Editor integration via Shell behaviour (AC: #2)
  - [x] Create `Planning.SpecReview.open_in_editor/2` — runs `$EDITOR <file_path>` via Shell behaviour
  - [x] Resolve editor: `System.get_env("EDITOR")` with fallback to `"vi"`
  - [x] DI: `shell_mod` opt, `editor_env` opt for testability
  - [x] After editor closes: stat-check the file, return `{:ok, %{modified: boolean}}`
  - [x] Tests: editor opens correct file, handles missing $EDITOR, detects file modification after edit (6 tests)

- [x] Task 3: CLI approval flow after generate-spec (AC: #1)
  - [x] After `fam generate-spec` succeeds, display summary and prompt
  - [x] Summary format: title, verified/unverified/convention counts, file path
  - [x] Interactive prompt deferred — `fam spec approve/reject/edit <id>` commands handle review
  - [x] DI: review_opts helper passes file_system, shell_mod, confirm_fn, editor_env from deps
  - [x] Tests: approve/reject/edit commands with stubs (6 tests in CLI)

- [x] Task 4: CLI spec approve/reject/edit commands (AC: #1, #2, #4)
  - [x] `fam spec approve <id>` — approve a spec directly (with stat-check + confirmation if modified)
  - [x] `fam spec reject <id>` — reject a spec
  - [x] `fam spec edit <id>` — open spec in $EDITOR via Shell behaviour
  - [x] All commands return `{:ok, %{id, title, status, ...}}` or `{:error, ...}`
  - [x] Tests: approve/reject/edit commands, error for non-existent spec, error for invalid ID (6 tests)

- [x] Task 5: Text formatters and help text (AC: #1)
  - [x] Text formatter reuses existing spec formatter for approve/reject
  - [x] Updated help text with spec approve/reject/edit commands
  - [x] JSON output via existing Output.format infrastructure

- [x] Task 6: Engine and Planning context delegation (AC: #4)
  - [x] `Engine.approve_spec/2`, `Engine.reject_spec/2`, `Engine.edit_spec/2` — delegate to SpecReview
  - [x] `Planning.approve_spec/2`, `Planning.reject_spec/2`, `Planning.edit_spec/2` — public API
  - [x] Tests: approve/reject delegation, error cases (4 tests)

### Review Findings

- [x] [Review][Decision] D1: Interactive prompt after generate-spec — fixed: print_spec_summary + run_approval_prompt loop [main.ex]
- [x] [Review][Decision] D2: Post-editor prompt loop — fixed: spec edit now calls run_approval_prompt after editor closes [main.ex]
- [x] [Review][Decision] D3: Approve re-reads modified file — fixed: handle_modification_check calls reload_if_modified [spec_review.ex]
- [x] [Review][Decision] D4: Frontmatter regex scoped — fixed: replace_frontmatter_status only modifies lines between --- delimiters [spec_review.ex]
- [x] [Review][Patch] P1: update_frontmatter error propagation — fixed: returns {:error, {:frontmatter_read/write_failed, ...}} [spec_review.ex]
- [x] [Review][Patch] P2: stat_check file-not-found — fixed: returns {:error, {:file_missing, ...}} instead of masking [spec_review.ex]
- [x] [Review][Patch] P3: Dead StubFileSystem removed [spec_review_test.exs]
- [x] [Review][Patch] P4: update_frontmatter error wrapping — fixed: fs.write error wrapped in {:error, {:frontmatter_write_failed, ...}} [spec_review.ex]
- [x] [Review][Patch] P5: nil updated_at guard — fixed: compare_mtime/2 returns true when updated_at is nil [spec_review.ex]
- [x] [Review][Defer] W1: normalize_status uses unbounded String.to_atom — pre-existing in engine.ex from Story 3.1, not introduced by this change

## Dev Notes

### Architecture Constraints

- **Hexagonal architecture**: File I/O through `FileSystem` behaviour, shell commands through `Shell` behaviour. No direct `File` or `System.cmd` calls.
- **Error tuples**: All public functions return `{:ok, result}` or `{:error, {atom, map}}`.
- **SecretFilter**: Not needed for approval flow — spec body is already filtered during generation.
- **Interactive prompts**: The CLI is synchronous — `IO.gets/1` for user input. DI via `prompt_fn` opt for testing.

### Existing Code to Reuse

| Module | API | Use For |
|--------|-----|---------|
| `Planning.Spec` | Ecto schema with status field | Status transitions (draft → approved/rejected) |
| `Planning.SpecGenerator` | `build_frontmatter/3` pattern | Reference for frontmatter format when rewriting |
| `Planning.Engine` | `get_spec/1`, `generate_spec/2` | Load spec for approval, generate before review |
| `Familiar.System.FileSystem` | `.read/1`, `.write/1`, `.stat/1` | Read/write spec files, stat-check for modifications |
| `Familiar.System.Shell` | `.cmd/3` | Run `$EDITOR` command |
| `Familiar.CLI.Main` | `run_spec_generation_with_trail/3` | Integrate approval prompt after generation |

### Key Design Decisions

**Frontmatter rewriting**: When approving/rejecting, the spec file's YAML frontmatter `status:` field must be updated. Read the file, regex-replace `status: draft` with the new status, write back. Don't regenerate the entire frontmatter — preserve user edits to the body.

**Stat-check flow**: Before approving, `FileSystem.stat/1` the spec file. Compare `mtime` against the spec's `updated_at` in DB. If file is newer, re-read and ask "The spec was modified externally. Approve the edited version? (y/n)". This catches $EDITOR edits and manual file edits.

**Editor flow**: `$EDITOR` is blocking — the Shell.cmd call waits for the editor to exit. On exit, stat-check → detect modification → re-prompt. If `$EDITOR` is not set, fall back to `vi`. If the editor command fails, return a clean error.

**Post-generate-spec prompt**: After `fam generate-spec` succeeds, the CLI should immediately show the summary and prompt. This replaces the current behavior where generate-spec just returns the result. The prompt is interactive (reads from stdin).

**Rejection returns to draft**: Rejecting a spec sets status to "rejected" in both DB and file. The user can re-plan or re-generate. The session stays "completed" — starting a new plan creates a new session.

### Previous Story Intelligence

**From Story 3.2:**
- Spec file path: `.familiar/specs/{session_id}-{slug}.md`
- Frontmatter format: title, session_id, status, generated_at, verified, unverified, conventions
- Session marked "completed" after spec generation — approval doesn't change session status
- `Spec.changeset/2` validates status in `~w(draft approved rejected)`
- Deferred D1: `generate_spec` CLI command — now implemented in Story 3.3 as `fam generate-spec <id>`

**From Story 3.3:**
- `fam generate-spec <id>` runs spec generation with trail display
- Trail events stream to stderr during generation
- `run_spec_generation_with_trail/3` is the integration point — approval prompt goes after this
- Channel `generate_spec` is now async (D1 fix) — result pushed via `spec:complete` event
- Trail module returns tagged tuples (`{:ok, :broadcast}`, etc.)
- 703 tests + 14 properties, 0 failures baseline

**From Story 3.1:**
- Engine public API pattern: `start_plan/2`, `respond/3`, `resume/1`, `generate_spec/2`, `get_spec/1`
- DI pattern: opts keyword list with `_mod` suffix for module injection
- Shell behaviour exists at `Familiar.System.Shell` but no `$EDITOR` usage yet

### Testing Standards

- **Mox for behaviours**: FileSystem (stat/read/write), Shell (cmd), Clock
- **Ecto sandbox**: `use Familiar.DataCase, async: true` where possible
- **DI for interactive prompts**: `prompt_fn` option to stub `IO.gets/1`
- **Near-100% coverage**: SpecReview module (critical approval logic)
- **Property tests**: Not required for this story (approval flow is not a pure function)

### Project Structure Notes

New files to create:
```
familiar/lib/familiar/planning/
└── spec_review.ex           # Approval, rejection, stat-check, editor integration

familiar/test/familiar/planning/
└── spec_review_test.exs     # Approval flow, stat-check, editor integration tests
```

Modified files:
```
familiar/lib/familiar/planning/engine.ex       # Add approve_spec/2, reject_spec/2
familiar/lib/familiar/planning/planning.ex     # Add approve_spec/2, reject_spec/2 delegation
familiar/lib/familiar/cli/main.ex              # Add spec approve/reject/edit commands, post-generation prompt
familiar/test/familiar/planning/engine_test.exs      # Approve/reject delegation tests
familiar/test/familiar/planning/planning_test.exs    # Delegation tests
familiar/test/familiar/cli/main_test.exs             # New command tests
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 3, Story 3.4]
- [Source: _bmad-output/planning-artifacts/prd.md — FR25]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Spec review page, approval flow, editor integration]
- [Source: _bmad-output/implementation-artifacts/3-2-spec-generation-verification.md — Spec schema, frontmatter format]
- [Source: _bmad-output/implementation-artifacts/3-3-streaming-reasoning-trail.md — generate-spec CLI, Trail integration]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Task 1: SpecReview module with approve/2, reject/2, stat_check/2, reload_if_modified/2. Frontmatter regex-replace preserves user edits. DI via file_system opt. 14 tests.
- Task 2: Editor integration via Shell behaviour — open_in_editor/2 with $EDITOR fallback to "vi", stat-check after editor closes. DI via shell_mod, editor_env. 5 tests.
- Task 3-4: CLI commands `fam spec approve <id>`, `fam spec reject <id>`, `fam spec edit <id>`. run_spec_action helper with review_opts DI passthrough. 6 CLI tests.
- Task 5: Help text updated with new commands. Existing text_formatter("spec") reused for approve/reject output.
- Task 6: Engine.approve_spec/2, reject_spec/2, edit_spec/2 delegating to SpecReview. Planning context delegation. 4 engine tests.
- Total: 29 new tests. Full suite: 732 tests + 14 properties, 0 failures. Credo strict: 0 issues.

### Change Log

- 2026-04-03: Story 3.4 implemented — Spec review and approval CLI with editor integration and stat-check

### File List

- familiar/lib/familiar/planning/spec_review.ex (new)
- familiar/lib/familiar/planning/engine.ex (modified — added approve_spec/2, reject_spec/2, edit_spec/2)
- familiar/lib/familiar/planning/planning.ex (modified — added approve_spec/2, reject_spec/2, edit_spec/2 delegation)
- familiar/lib/familiar/cli/main.ex (modified — added spec approve/reject/edit commands, help text)
- familiar/test/familiar/planning/spec_review_test.exs (new)
- familiar/test/familiar/planning/engine_test.exs (modified — added approve/reject tests)
- familiar/test/familiar/cli/main_test.exs (modified — added spec approve/reject/edit tests)
