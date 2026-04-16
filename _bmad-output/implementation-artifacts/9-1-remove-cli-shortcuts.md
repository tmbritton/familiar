# Story 9-1: Remove Hardcoded CLI Shortcuts (plan/do/fix)

Status: review

## Story

As a Familiar user,
I want the CLI to not assume I'm doing software engineering,
So that the command surface is domain-neutral and workflows are invoked by their actual names.

## Acceptance Criteria

1. **AC1: Command handlers deleted.** No `run_with_daemon` clause in `main.ex` matches `"plan"`, `"do"`, or `"fix"` as commands. The `run_workflow_command/4` private function does not exist.

2. **AC2: Planning resume deleted.** The `resume_planning/2`, `find_planning_conversation/1` (both arities), and `resume_with_context/3` private functions do not exist. Planning resume is handled by the existing `fam workflows resume` command (Story 7.5-6).

3. **AC3: Text formatter cleaned.** The `text_formatter(cmd) when cmd in ~w(plan do fix)` clause does not exist. The workflow text formatter used by `fam workflows run` is unaffected.

4. **AC4: Help text updated.** `help_text/0` does not mention `plan`, `do`, or `fix` as commands. The `workflows` section includes `workflows run <name> <desc>` to guide users to the generic path.

5. **AC5: Test file deleted.** `test/familiar/cli/workflow_commands_test.exs` (339 lines) does not exist.

6. **AC6: Main test updated.** `test/familiar/cli/main_test.exs` no longer contains `describe "parse_args/1 for plan command"` or `describe "run/2 with plan command"` blocks. The `search --raw` parse test (currently inside the plan describe block) is preserved by moving it to an appropriate describe block.

7. **AC7: Generic workflow path untouched.** `run_workflow/4`, `fam workflows run`, `fam workflows resume`, `text_formatter("workflows")`, and `quiet_summary(%{workflow: _, steps: _})` all remain functional and unchanged.

8. **AC8: Shared helpers preserved.** `format_conversation_context/1` stays — it is used by `load_and_resume_chat/2`. The `--resume` and `--session` flags stay in `parse_args` — they are used by `chat --resume`.

9. **AC9: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass with zero warnings/failures.

10. **AC10: Stress-tested.** Every touched test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Delete plan/do/fix command handlers from main.ex (AC: 1)
  - [x] Delete `run_with_daemon({"plan", ...})` — all 4 clauses (lines 357–372)
  - [x] Delete `run_with_daemon({"do", ...})` — both clauses (lines 374–380)
  - [x] Delete `run_with_daemon({"fix", ...})` — both clauses (lines 382–388)
  - [x] Delete `run_workflow_command/4` (lines 1425–1434)

- [x] Task 2: Delete planning resume helpers (AC: 2)
  - [x] Delete `resume_planning/2` (lines 1456–1472)
  - [x] Delete `find_planning_conversation/1` — nil arity (lines 1474–1478)
  - [x] Delete `find_planning_conversation/1` — integer arity (lines 1481–1483)
  - [x] Delete `resume_with_context/3` (lines 1485–1498)
  - [x] Verify `format_conversation_context/1` stays (used by chat resume at line 1537)

- [x] Task 3: Delete text formatter clause (AC: 3)
  - [x] Delete `text_formatter(cmd) when cmd in ~w(plan do fix)` (lines 2222–2240)

- [x] Task 4: Update help text (AC: 4)
  - [x] Remove `plan <description>` line from help_text (line 2761)
  - [x] Remove `do <description>` line from help_text (line 2762)
  - [x] Remove `fix <description>` line from help_text (line 2763)
  - [x] Add `workflows run <name> <desc>  Run a workflow by name` under the workflows section

- [x] Task 5: Delete workflow_commands_test.exs (AC: 5)
  - [x] Delete `test/familiar/cli/workflow_commands_test.exs` (339 lines)

- [x] Task 6: Update main_test.exs (AC: 6, 8)
  - [x] Delete `describe "parse_args/1 for plan command"` block, preserved `search --raw` test in new `describe "parse_args/1 for search command"` block
  - [x] Delete `describe "run/2 with plan command"` block (lines 821–843)

- [x] Task 6b: Update workflow_integration_test.exs (discovered during implementation)
  - [x] Updated 7 tests to use `{"workflows", ["run", "<name>", ...]}` instead of `{"plan"/"do"/"fix", ...}`
  - [x] Updated planning scope test to agent scope (workflows run always uses "agent" scope)

- [x] Task 6c: Wire up `fam workflows run` handler (discovered during implementation)
  - [x] Added `run_with_daemon({"workflows", ["run", name | rest], _flags})` handler
  - [x] Added workflow run result clause to `text_formatter("workflows")` — `%{workflow: _, steps: _} when is_list(steps)`
  - [x] Updated init success message from `fam plan` reference to `fam chat`

- [x] Task 7: Toolchain verification (AC: 9)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1304 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 8: Stress-test touched files (AC: 10)
  - [x] 50x run on main_test.exs + workflow_integration_test.exs — 51/51 clean

## Dev Notes

### What to delete

| File | Lines | Action |
|------|-------|--------|
| `lib/familiar/cli/main.ex` | 357–372 | Delete plan command handlers (4 clauses) |
| `lib/familiar/cli/main.ex` | 374–380 | Delete do command handlers (2 clauses) |
| `lib/familiar/cli/main.ex` | 382–388 | Delete fix command handlers (2 clauses) |
| `lib/familiar/cli/main.ex` | 1425–1434 | Delete `run_workflow_command/4` |
| `lib/familiar/cli/main.ex` | 1456–1498 | Delete `resume_planning`, `find_planning_conversation` (2), `resume_with_context` |
| `lib/familiar/cli/main.ex` | 2222–2240 | Delete `text_formatter(cmd) when cmd in ~w(plan do fix)` |
| `lib/familiar/cli/main.ex` | 2761–2763 | Delete plan/do/fix from help text |
| `test/familiar/cli/workflow_commands_test.exs` | All (339) | Delete entire file |
| `test/familiar/cli/main_test.exs` | 801–843 | Delete plan parse/run describe blocks |

### What to modify

| File | Change |
|------|--------|
| `lib/familiar/cli/main.ex` help_text | Add `workflows run <name> <desc>` line |
| `test/familiar/cli/main_test.exs` | Move `search --raw` parse test out of plan describe block |

### What NOT to touch

- **`run_workflow/4`** (line 1436) — generic workflow runner, used by `fam workflows run`. Stays.
- **`format_conversation_context/1`** (line 1500) — shared with `load_and_resume_chat/2`. Stays.
- **`--resume` / `--session` flags** in `parse_args` — used by `chat --resume`. Stay.
- **`text_formatter("workflows")`** — separate clause for `fam workflows` output. Stays.
- **`quiet_summary(%{workflow: _, steps: _})`** in `output.ex` — generic workflow summary. Stays.
- **`quiet_summary(%{chat: _, status: _})`** in `output.ex` — chat summary. Stays.
- **`fam workflows resume`** (line 679) — the generic resume that already exists. Stays.

### Architecture context

The `plan`/`do`/`fix` commands are thin wrappers that map a command name to a hardcoded workflow filename:
- `plan` → `feature-planning.md`
- `do` → `feature-implementation.md`
- `fix` → `task-fix.md`

The generic `fam workflows run <name> <description>` already supports running any workflow by name, making these shortcuts redundant. The `plan` command also has resume logic (`--resume`, `--session`) that duplicates what `fam workflows resume` already provides.

After deletion, users run workflows with:
```
fam workflows run feature-planning "add user authentication"
fam workflows run feature-implementation "implement the auth module"
fam workflows resume
```

### Previous story patterns

- **Pure subtraction** — this is a deletion story, like 7.6-1 (Safety removal). No replacement code needed.
- **Move, don't lose** — the `search --raw` test is inside the plan describe block but tests search functionality. Move it, don't delete it.
- **50x stress test** — zero-tolerance flaky test policy on all modified test files.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 9] — Epic description and story scope
- [Source: familiar/lib/familiar/cli/main.ex:357–388] — plan/do/fix command handlers
- [Source: familiar/lib/familiar/cli/main.ex:1425–1507] — run_workflow_command, resume_planning helpers
- [Source: familiar/lib/familiar/cli/main.ex:2222–2240] — text_formatter for plan/do/fix
- [Source: familiar/lib/familiar/cli/main.ex:2761–2763] — help text entries
- [Source: familiar/test/familiar/cli/workflow_commands_test.exs] — 339-line test file to delete
- [Source: familiar/test/familiar/cli/main_test.exs:801–843] — plan parse/run tests to delete
- [Source: familiar/lib/familiar/cli/main.ex:679] — existing `fam workflows resume` handler

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Discovered `run_workflow/4` was only called by the deleted plan/do/fix handlers — no existing `fam workflows run` handler existed. Added one.
- `format_conversation_context/1` confirmed shared with chat resume — kept.
- Init success message referenced `fam plan` — updated to `fam chat`.

### Completion Notes List

- Deleted 8 `run_with_daemon` clauses for plan/do/fix commands from main.ex
- Deleted `run_workflow_command/4`, `resume_planning/2`, `find_planning_conversation/1` (2 arities), `resume_with_context/3`
- Deleted `text_formatter(cmd) when cmd in ~w(plan do fix)` clause
- Removed plan/do/fix from help text, added `workflows run <name> <desc>`
- Added `run_with_daemon({"workflows", ["run", ...]})` handler — without this, no CLI path existed to run workflows
- Added `%{workflow: _, steps: _}` clause to `text_formatter("workflows")` for workflow run output
- Updated init success message: `fam plan` → `fam chat`
- Deleted `workflow_commands_test.exs` (339 lines)
- Updated `main_test.exs` — removed plan describe blocks, preserved search --raw test
- Updated `workflow_integration_test.exs` — 7 tests updated to use `workflows run` path
- Test count: 1330 → 1304 (26 tests removed — plan/do/fix CLI tests)
- 50x stress test on main_test.exs + workflow_integration_test.exs: 51/51 clean

### File List

**Deleted:**
- familiar/test/familiar/cli/workflow_commands_test.exs

**Modified:**
- familiar/lib/familiar/cli/main.ex
- familiar/test/familiar/cli/main_test.exs
- familiar/test/familiar/execution/workflow_integration_test.exs

### Change Log

- 2026-04-16: Story 9-1 implemented — removed plan/do/fix CLI shortcuts, added generic `fam workflows run` handler
