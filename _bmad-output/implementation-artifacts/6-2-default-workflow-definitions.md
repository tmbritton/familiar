# Story 6.2: Default Workflow Definitions

Status: done

## Story

As a user running `fam plan`, `fam do`, or `fam fix`,
I want the default workflow files to define complete step pipelines with input references between steps,
so that each step receives context from prior steps and the workflow produces coherent end-to-end results.

## Context

Story 6-1 added basic YAML frontmatter to the 3 default workflows, but the steps don't use `input` references — each step runs in isolation without seeing what the previous step produced. For example, the `review-spec` step in `feature-planning.md` should receive the output from `draft-spec` so the reviewer sees the specification it's reviewing.

This story enriches the workflow definitions and validates they parse and execute correctly through WorkflowRunner.

## Acceptance Criteria

### AC1: Workflow Steps Use Input References

**Given** the default workflow files
**When** parsed by WorkflowRunner
**Then** later steps reference earlier step outputs via the `input` field
**And** `validate_step_inputs/1` passes (no forward or self-references)

### AC2: WorkflowRunner Successfully Parses All Default Workflows

**Given** the 3 default workflow files installed by `DefaultFiles.install/1`
**When** `WorkflowRunner.parse_workflow/1` is called on each
**Then** each returns `{:ok, %Workflow{}}` with the correct step count, names, and roles

### AC3: Workflows Execute End-to-End with Mocked LLM

**Given** a parsed default workflow
**When** `WorkflowRunner.run_workflow/3` is called with a mocked LLM provider
**Then** the workflow completes successfully with step results from each step
**And** later steps receive context from earlier steps in their task description

### AC4: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: Enrich workflow step definitions with input references (AC: 1)
  - [x] `feature-planning.md`: `draft-spec` inputs from `research`, `review-spec` inputs from `draft-spec`
  - [x] `feature-implementation.md`: `test` inputs from `implement`, `review` inputs from `implement` and `test`
  - [x] `task-fix.md`: `fix` inputs from `diagnose`, `verify` inputs from `fix`

- [x] Task 2: Add WorkflowRunner parse validation test (AC: 2)
  - [x] `WorkflowRunner.parse/1` succeeds on all 3 default workflow files
  - [x] Assert correct step count (3), names, and roles
  - [x] Validate input references: first step has none, later steps reference only prior steps

- [x] Task 3: Add workflow execution integration test (AC: 3)
  - [x] All 3 workflows run end-to-end with mocked LLM using DefaultFiles.install
  - [x] Assert 3 steps complete with correct step names
  - [x] Verify later steps receive prior step context in task description

- [x] Task 4: Verify all existing tests pass (AC: 4)
  - [x] 972 tests + 8 properties, 0 failures. Credo strict: 0 issues.

## Dev Notes

### Input References

The `input` field on a step is a list of prior step names whose output should be included in the task description for the current step. WorkflowRunner's `format_previous_steps/2` builds the context string from these.

```yaml
steps:
  - name: research
    role: analyst
  - name: draft-spec
    role: analyst
    input:
      - research
  - name: review-spec
    role: reviewer
    input:
      - draft-spec
```

### WorkflowRunner.parse_workflow/1

Reads a markdown file, extracts YAML frontmatter, builds `%Workflow{}` with `%Step{}` structs. Already exists and is tested — this story just validates it works with the actual default files.

### Test Approach for Execution

WorkflowRunner spawns AgentProcess for each step, which calls the LLM. In tests, the LLM is mocked via `Familiar.Providers.LLMMock`. Each agent needs a role file on disk. Use `DefaultFiles.install/1` to get both workflow and role files, then run the workflow.

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/knowledge/default_files.ex` | Add `input` references to workflow step definitions |
| `familiar/test/familiar/knowledge/default_files_test.exs` | Add parse validation test |
| `familiar/test/familiar/execution/workflow_runner_test.exs` | Add execution integration test (or new file) |

### References

- [Source: familiar/lib/familiar/execution/workflow_runner.ex:484-501] — `build_step/1` parses `input` field
- [Source: familiar/lib/familiar/execution/workflow_runner.ex:360-373] — `build_task_description/2` includes previous step context
- [Source: familiar/lib/familiar/execution/workflow_runner.ex:376-392] — `format_previous_steps/2` builds context from step results

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Added `input` references to all 3 default workflows: later steps reference prior steps for context passing
- Added 2 parse validation tests: WorkflowRunner.parse/1 succeeds, input references are valid
- Added 4 execution integration tests: all 3 workflows run end-to-end, context flows between steps
- 972 tests + 8 properties, 0 failures. Credo strict: 0 issues.

### File List

- `familiar/lib/familiar/knowledge/default_files.ex` — added input references to workflow step definitions
- `familiar/test/familiar/knowledge/default_files_test.exs` — 2 new parse/input validation tests
- `familiar/test/familiar/execution/workflow_runner_test.exs` — 4 new execution integration tests
