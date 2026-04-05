# Story 6.3: CLI Workflow Dispatch

Status: done

## Story

As a developer using the `fam` CLI,
I want `fam plan`, `fam do`, and `fam fix` to execute the corresponding default workflows via WorkflowRunner,
so that I can run multi-step agent workflows from the command line with a single command.

## Context

Stories 6-1 and 6-2 created and enriched the 3 default workflow files (`feature-planning.md`, `feature-implementation.md`, `task-fix.md`) with correct YAML frontmatter and input references. WorkflowRunner already has a working `run_workflow/3` API that parses a workflow file and executes it end-to-end.

The CLI (`Familiar.CLI.Main`) currently has placeholder stubs for `plan`, `generate-spec`, and `spec` that return `{:error, {:not_implemented, ...}}`. This story replaces those stubs with real workflow dispatch, adds the new `do` and `fix` commands, and wires everything through the existing DI-based command dispatch pattern.

## Acceptance Criteria

### AC1: `fam plan <description>` Runs Feature-Planning Workflow

**Given** the `.familiar/` directory exists with default workflow files
**When** the user runs `fam plan "Add user authentication"`
**Then** the CLI resolves the `feature-planning.md` workflow file
**And** calls `WorkflowRunner.run_workflow/3` with `%{task: "Add user authentication"}`
**And** returns `{:ok, %{workflow: "feature-planning", steps: [...]}}` on success
**And** returns `{:error, reason}` on workflow failure

### AC2: `fam do <description>` Runs Feature-Implementation Workflow

**Given** the `.familiar/` directory exists with default workflow files
**When** the user runs `fam do "Implement login form"`
**Then** the CLI resolves the `feature-implementation.md` workflow file
**And** calls `WorkflowRunner.run_workflow/3` with `%{task: "Implement login form"}`
**And** returns step results on success

### AC3: `fam fix <description>` Runs Task-Fix Workflow

**Given** the `.familiar/` directory exists with default workflow files
**When** the user runs `fam fix "Fix broken redirect"`
**Then** the CLI resolves the `task-fix.md` workflow file
**And** calls `WorkflowRunner.run_workflow/3` with `%{task: "Fix broken redirect"}`
**And** returns step results on success

### AC4: Error Handling for Missing Description

**Given** the CLI
**When** the user runs `fam plan` (no description)
**Then** returns `{:error, {:usage_error, %{message: "Usage: fam plan <description>"}}}` (and similarly for `do` and `fix`)

### AC5: Error Handling for Missing Workflow File

**Given** the default workflow file does not exist (e.g., user deleted it)
**When** the user runs `fam plan "something"`
**Then** returns `{:error, {:file_error, ...}}` from WorkflowRunner.parse

### AC6: Output Formatting

**Given** a successful workflow run
**When** output is formatted in text mode
**Then** each step name and a summary of its output is displayed
**When** output is formatted in JSON mode
**Then** the full result map is returned as JSON

### AC7: Dependency Injection for Testability

**Given** the run function's `deps` map
**When** a `workflow_fn` key is present
**Then** it is called instead of `WorkflowRunner.run_workflow/3`
**And** CLI tests can verify dispatch without spawning real agents

### AC8: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: Replace `plan` stub with workflow dispatch (AC: 1, 4, 5, 7)
  - [x] Replace `run_with_daemon({"plan", _, _}, _deps)` stub with real implementation
  - [x] Extract task description from args: `Enum.join(args, " ")`
  - [x] Resolve workflow path: `Path.join([Paths.familiar_dir(), "workflows", "feature-planning.md"])`
  - [x] Call `workflow_fn.(path, %{task: description}, [])` where `workflow_fn` defaults to `&WorkflowRunner.run_workflow/3`
  - [x] Return `{:ok, %{workflow: "feature-planning", steps: result.steps}}`
  - [x] Handle empty args → usage error

- [x] Task 2: Add `do` and `fix` commands (AC: 2, 3, 4, 5, 7)
  - [x] Add `run_with_daemon({"do", args, _flags}, deps)` dispatching to `feature-implementation.md`
  - [x] Add `run_with_daemon({"fix", args, _flags}, deps)` dispatching to `task-fix.md`
  - [x] Same pattern as `plan`: extract description, resolve path, call workflow_fn
  - [x] Handle empty args → usage error for each

- [x] Task 3: Add text formatters for workflow commands (AC: 6)
  - [x] Add `text_formatter("plan")`, `text_formatter("do")`, `text_formatter("fix")`
  - [x] Format: print each step name and truncated output (first 200 chars)
  - [x] Include workflow name in header

- [x] Task 4: Update help text (AC: 1, 2, 3)
  - [x] Add `do <description>` and `fix <description>` to help_text
  - [x] Update `plan` description to remove reference to "web UI or API"
  - [x] Remove or update `generate-spec` and `spec` stubs (these are subsumed by workflow commands)

- [x] Task 5: Write CLI tests (AC: 1-7)
  - [x] Test `parse_args` for plan, do, fix commands
  - [x] Test dispatch with injected `workflow_fn` for each command
  - [x] Test usage error for missing description
  - [x] Test error propagation from workflow failure
  - [x] Test text and JSON output formatting

- [x] Task 6: Verify test baseline (AC: 8)
  - [x] All tests pass with 0 failures
  - [x] Credo strict: 0 issues

## Dev Notes

### Existing CLI Dispatch Pattern

The CLI uses a DI-based pattern. `run/2` takes `{command, args, flags}` and a `deps` map. Commands that need the daemon go through `run_with_daemon/2`. Each command is a separate function clause pattern-matching on the command name.

Key DI pattern from existing code (`init_command_test.exs`):
```elixir
deps = init_deps(
  workflow_fn: fn path, context, _opts ->
    {:ok, %{steps: [%{step: "research", output: "found stuff"}]}}
  end
)
Main.run({"plan", ["Add auth"], %{}}, deps)
```

### WorkflowRunner API

```elixir
WorkflowRunner.run_workflow(path, context \\ %{}, opts \\ [])
# Returns {:ok, %{steps: [%{step: name, output: result}]}} or {:error, reason}
```

The `run_workflow/3` function blocks until completion. For MVP this is fine — the CLI process waits while agents execute. Async/streaming output is a future enhancement.

### Workflow File Resolution

Workflow files live at `.familiar/workflows/<name>.md`. The path is resolved via:
```elixir
Path.join([Paths.familiar_dir(), "workflows", "feature-planning.md"])
```

### Command-to-Workflow Mapping

| CLI Command | Workflow File | Description |
|-------------|--------------|-------------|
| `fam plan <desc>` | `feature-planning.md` | Research → draft-spec → review-spec |
| `fam do <desc>` | `feature-implementation.md` | Implement → test → review |
| `fam fix <desc>` | `task-fix.md` | Diagnose → fix → verify |

### Stubs to Replace

Lines 178-200 in `main.ex` have three placeholder stubs (`plan`, `generate-spec`, `spec`) that return `:not_implemented`. Replace `plan` with real dispatch. The `generate-spec` and `spec` stubs are from the old bespoke planning model (pre-reframing) and should be removed — they're subsumed by `fam plan` running the feature-planning workflow.

### Output Formatter Pattern

Existing formatters in `text_formatter/1` return a function `fn data -> formatted_string end`. For workflow results:
```
Workflow: feature-planning (3 steps)

  1. research — Found relevant patterns in auth module...
  2. draft-spec — Specification: ## User Authentication...
  3. review-spec — LGTM with minor suggestions...
```

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/cli/main.ex` | Replace plan stub, add do/fix commands, update help text, add formatters |
| `familiar/test/familiar/cli/workflow_commands_test.exs` | **New file** — tests for plan/do/fix CLI dispatch |

### References

- [Source: familiar/lib/familiar/cli/main.ex:178-200] — current placeholder stubs
- [Source: familiar/lib/familiar/cli/main.ex:80-116] — command dispatch pattern with DI
- [Source: familiar/lib/familiar/cli/main.ex:945-975] — help text
- [Source: familiar/lib/familiar/execution/workflow_runner.ex:140-164] — run_workflow/3 API
- [Source: familiar/test/familiar/cli/init_command_test.exs] — DI test pattern example
- [Source: familiar/lib/familiar/cli/output.ex:27-68] — output format modes

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Replaced 3 placeholder stubs (`plan`, `generate-spec`, `spec`) with real workflow dispatch via shared `run_workflow_command/3` helper
- Added `fam do` and `fam fix` commands mapping to `feature-implementation.md` and `task-fix.md`
- DI via `workflow_fn` in deps map — defaults to `&WorkflowRunner.run_workflow/3`
- Single text formatter handles all 3 commands via guard: `when cmd in ~w(plan do fix)`
- Updated help text with new commands, removed obsolete spec-related entries
- Updated 5 existing MainTest tests that expected `:not_implemented` stubs
- 14 new tests in workflow_commands_test.exs covering dispatch, errors, and formatting
- 986 tests + 8 properties, 0 failures. Credo strict: 0 issues.
- Code review fixes: whitespace-only description guard, quiet_summary clause for workflow results, removed duplicated formatter from tests

### File List

- `familiar/lib/familiar/cli/main.ex` — replaced stubs, added do/fix commands, updated help and formatters
- `familiar/lib/familiar/cli/output.ex` — added quiet_summary clause for workflow results
- `familiar/test/familiar/cli/workflow_commands_test.exs` — **new** — 14 tests for workflow CLI dispatch
- `familiar/test/familiar/cli/main_test.exs` — updated 5 tests for new plan/spec/generate-spec behavior
