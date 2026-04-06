# Story 6.5: Workflow Integration Test

Status: done

## Story

As a developer maintaining the Familiar harness,
I want an end-to-end integration test that validates the complete workflow pipeline from CLI dispatch through WorkflowRunner to agent execution,
so that regressions in the workflow system are caught before they reach users.

## Context

Stories 6-1 through 6-4 built the full workflow pipeline: default role/skill/workflow files, CLI dispatch (`fam plan/do/fix`), WorkflowRunner with interactive mode, and session resume. Each story has unit-level and component-level tests, but there is no single integration test that exercises the full pipeline end-to-end with real default files.

The existing `harness_integration_test.exs` (Story 5-10) validates the agent harness with hand-built workflows. This story adds a workflow-specific integration test that uses the actual shipped default files and CLI dispatch path.

## Acceptance Criteria

### AC1: Full Pipeline Integration — CLI Through Workflow Completion

**Given** default workflow, role, and skill files installed via `DefaultFiles.install/1`
**When** `Main.run({"plan", ["Plan auth"], %{}}, deps)` is called with a real `WorkflowRunner.run_workflow/3` (not mocked)
**Then** the feature-planning workflow executes all 3 steps (research, draft-spec, review-spec)
**And** each step spawns an AgentProcess with the correct role
**And** the result contains step outputs from the mocked LLM
**And** the interactive draft-spec step completes via the injected `input_fn`

### AC2: All Three Default Workflows Execute Successfully

**Given** default files installed
**When** each of `feature-planning.md`, `feature-implementation.md`, and `task-fix.md` is dispatched via the CLI
**Then** all three complete with correct step counts and step names

### AC3: Context Flows Between Steps

**Given** a multi-step workflow with input references
**When** a later step executes
**Then** its task description includes output from the referenced prior steps
**And** the context is correctly formatted with step names and truncated output

### AC4: Conversation Persistence Verified

**Given** a completed workflow run
**When** conversations are queried from the database
**Then** each step created a conversation with the correct scope
**And** each conversation has system, user, and assistant messages persisted

### AC5: Error Propagation End-to-End

**Given** a workflow where a step's LLM call fails
**When** the workflow runs via CLI dispatch
**Then** the error propagates as `{:error, {:step_failed, %{step: name}}}` to the CLI
**And** completed steps before the failure have their results preserved

### AC6: Workflow File Validation Errors

**Given** a malformed workflow file (missing name, bad YAML, missing role)
**When** dispatched via the CLI
**Then** a clear error is returned (not a crash)
**And** the error identifies what is wrong

### AC7: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: Create workflow integration test file (AC: 1, 2, 3, 4)
  - [x] New file: `test/familiar/execution/workflow_integration_test.exs`
  - [x] Use `Familiar.DataCase, async: false` with Mox global mode
  - [x] Setup: install default files via `DefaultFiles.install/1` in tmp_dir
  - [x] Setup: DynamicSupervisor for agent isolation
  - [x] Setup: LLM mock with interactive-aware stub (signal_ready on 2nd user msg)
  - [x] Setup: `input_fn` that auto-responds for interactive steps

- [x] Task 2: CLI → workflow pipeline test (AC: 1)
  - [x] Test `Main.run({"plan", ["Plan auth"], %{}}, deps)` with real `workflow_fn`
  - [x] Verify result has `workflow: "feature-planning"` and 3 steps
  - [x] Verify step names match expected order

- [x] Task 3: All three workflows via CLI (AC: 2)
  - [x] Test plan, do, fix commands each complete successfully
  - [x] Verify step counts and names for each

- [x] Task 4: Context flow between steps (AC: 3)
  - [x] Instrument LLM mock to capture task descriptions per step
  - [x] Verify later steps' task descriptions include prior step output
  - [x] Verify input references are resolved correctly

- [x] Task 5: Conversation persistence (AC: 4)
  - [x] After workflow completion, query conversations by scope
  - [x] Verify correct number of conversations created
  - [x] Verify messages exist for each conversation

- [x] Task 6: Error propagation test (AC: 5)
  - [x] Create a role that triggers LLM failure (FAIL_MODE)
  - [x] Run workflow with failing step, verify error structure
  - [x] Test workflow with missing role file returns error

- [x] Task 7: Validation error tests (AC: 6)
  - [x] Test with malformed YAML workflow file
  - [x] Test with missing name field
  - [x] Test with step missing role
  - [x] Test with nonexistent file

- [x] Task 8: Verify test baseline (AC: 7)
  - [x] All tests pass with 0 failures
  - [x] Credo strict: 0 issues

## Dev Notes

### Test Architecture

This is a single integration test file that exercises the full pipeline. It uses:
- Real `DefaultFiles.install/1` for workflow/role/skill files
- Real `WorkflowRunner.run_workflow/3` (not mocked) — passed as `workflow_fn` in deps
- Real `AgentProcess` spawned under a test DynamicSupervisor
- Mocked LLM (returns role-based responses, handles interactive signal_ready)
- Mocked embedder, file system, clock (same as harness_integration_test)
- Real Ecto/SQLite for conversation persistence

### CLI deps Setup

The CLI test needs a deps map with `workflow_fn` pointing to the real implementation:

```elixir
deps = %{
  ensure_running_fn: fn _opts -> {:ok, 4000} end,
  health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
  daemon_status_fn: fn _opts -> {:stopped, %{}} end,
  stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end,
  workflow_fn: &WorkflowRunner.run_workflow/3,
  input_fn: fn _step, _content -> {:ok, "User response"} end
}
```

### Interactive Step Handling

The default `feature-planning.md` has `mode: interactive` on `draft-spec`. The LLM mock must handle this by calling `signal_ready` after user input. Use the same pattern from `workflow_runner_test.exs`: check `user_msgs >= 2 and tool_msgs == 0`.

Re-register `signal_ready` tool before each test to prevent the `tool_registry_test` interference discovered in Story 6.4.

### Conversation Verification

After a workflow completes, verify persistence:
```elixir
# Query conversations created during the test
{:ok, convs} = Repo.all(from c in Conversation, where: c.scope == "planning")
assert length(convs) == 3  # one per step
```

### Files to Create/Modify

| File | Change |
|------|--------|
| `familiar/test/familiar/execution/workflow_integration_test.exs` | **New file** — integration tests |

### References

- [Source: familiar/test/familiar/execution/harness_integration_test.exs] — integration test patterns
- [Source: familiar/test/familiar/execution/workflow_runner_test.exs:438-549] — default workflow tests
- [Source: familiar/test/familiar/cli/workflow_commands_test.exs] — CLI dispatch tests
- [Source: familiar/lib/familiar/knowledge/default_files.ex] — default file definitions
- [Source: familiar/lib/familiar/cli/main.ex:360-385] — CLI workflow dispatch

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- 12 new integration tests in single file covering full CLI→WorkflowRunner→AgentProcess pipeline
- All 3 default workflows tested end-to-end via CLI dispatch with real WorkflowRunner
- Context flow verified: review step sees implement+test output, test step sees implement output
- Conversation persistence: verified per-step conversations with messages, planning scope for plan command
- Error propagation: FAIL_MODE role triggers step_failed, missing role returns error
- Validation: malformed YAML, missing name, missing role, nonexistent file — all return clear errors
- 1007 tests + 8 properties, 0 failures. Credo strict: 0 issues.

### File List

- `familiar/test/familiar/execution/workflow_integration_test.exs` — **new** — 12 integration tests
