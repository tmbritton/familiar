# Story 6.4: Planning as Workflow

Status: done

## Story

As a developer using `fam plan`,
I want the feature-planning workflow to support interactive multi-turn conversations and session resume,
so that I can have an iterative planning dialogue with the analyst agent and pick up where I left off.

## Context

Story 6-3 wired `fam plan <description>` to dispatch `feature-planning.md` through WorkflowRunner. Currently this runs in autonomous mode — the analyst agent runs once and returns a result. But effective planning requires back-and-forth: the analyst asks clarifying questions, the user answers, and the conversation builds toward a specification.

The infrastructure already exists:
- WorkflowRunner parses `mode: interactive` from YAML frontmatter
- AgentProcess creates conversations via `Conversations.create/2` and persists all messages
- `Conversations.latest_active/1` can find a resumable session
- The CLI already parses `--resume` and `--session` flags (currently dead code from Story 6-3)

This story connects these pieces: update the workflow definition to use interactive mode for the draft-spec step, wire the CLI's `--resume` flag to resume the latest planning conversation, and ensure the analyst role prompts for user input rather than guessing.

Architecture Decision A3 states: "Planning is a workflow definition executed by agents through the generic workflow runner — the same execution environment used for implementation, fixing, and custom workflows."

## Acceptance Criteria

### AC1: Feature-Planning Workflow Uses Interactive Mode for Draft-Spec

**Given** the `feature-planning.md` default workflow
**When** parsed by WorkflowRunner
**Then** the `draft-spec` step has `mode: interactive`
**And** the `research` and `review-spec` steps remain `mode: autonomous` (default)

### AC2: Interactive Step Prompts for User Input

**Given** a workflow step with `mode: interactive`
**When** the agent produces a response that ends with a question or asks for clarification
**Then** the WorkflowRunner pauses execution and returns the response to the CLI
**And** the CLI displays the response and waits for user input
**And** user input is sent back to the agent as a follow-up message

### AC3: `fam plan --resume` Resumes Latest Planning Conversation

**Given** a previous `fam plan` session that was interrupted or paused
**When** the user runs `fam plan --resume`
**Then** the CLI finds the latest active planning conversation via `Conversations.latest_active/1`
**And** resumes the workflow from where it left off
**And** returns `{:error, {:no_active_conversation, ...}}` if no session exists

### AC4: `fam plan --session <id>` Resumes a Specific Session

**Given** a specific conversation ID
**When** the user runs `fam plan --session 42`
**Then** the CLI resumes that specific planning conversation
**And** returns an error if the conversation doesn't exist or is already completed

### AC5: Interactive Mode Reads User Input from stdin

**Given** an interactive workflow step running in the CLI
**When** the agent asks for user input
**Then** the CLI reads from stdin (via `IO.gets/1` or injected `input_fn`)
**And** sends the user's response back to the agent
**And** the conversation continues until the agent signals completion

### AC6: Conversation Persistence Across Steps

**Given** a multi-step workflow with interactive steps
**When** the workflow completes
**Then** all conversation messages (system, user, assistant, tool) are persisted
**And** each step's conversation is linked to its agent_id

### AC7: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: Update feature-planning workflow to use interactive mode (AC: 1)
  - [x] Set `mode: interactive` on `draft-spec` step in `default_files.ex`
  - [x] Update the `default_files_test.exs` parse test to verify interactive mode

- [x] Task 2: Implement interactive step execution in WorkflowRunner (AC: 2, 5)
  - [x] When step mode is `:interactive`, WorkflowRunner enters a read-eval loop
  - [x] After agent responds, check if agent called `signal_ready` — if so, step is complete
  - [x] If not, return response to caller and wait for user input
  - [x] Send user input as new message to the agent, continue loop
  - [x] Add `input_fn` option to WorkflowRunner for DI (defaults to `IO.gets/IO.puts`)
  - [x] Timeout handling: agent pauses timeout while waiting for user input

- [x] Task 3: Wire `--resume` and `--session` flags in CLI (AC: 3, 4)
  - [x] `fam plan --resume` calls `Conversations.latest_active(scope: "planning")`
  - [x] `fam plan --session 42` calls `Conversations.get(42)` and validates status
  - [x] Resume loads conversation messages and passes as context to new workflow run
  - [x] Update `run_with_daemon({"plan", ...})` to handle flags before dispatching

- [x] Task 4: Add planning conversation scope (AC: 3, 6)
  - [x] When `fam plan` creates a workflow, pass `scope: "planning"` to conversation
  - [x] Ensure `latest_active(scope: "planning")` only finds planning sessions
  - [x] Add scope parameter threading from CLI → WorkflowRunner → AgentProcess

- [x] Task 5: Write tests (AC: 1-7)
  - [x] Test interactive mode parsing in workflow definition
  - [x] Test WorkflowRunner interactive loop with mocked agent and input_fn
  - [x] Test --resume finds latest planning conversation
  - [x] Test --session resumes specific conversation
  - [x] Test error when no active session exists for --resume
  - [x] Test conversation persistence across interactive steps

- [x] Task 6: Verify test baseline (AC: 7)
  - [x] All tests pass with 0 failures
  - [x] Credo strict: 0 issues

## Dev Notes

### WorkflowRunner Interactive Mode

The `Step` struct already has `mode: :autonomous | :interactive`. Currently, WorkflowRunner treats both the same — it spawns an agent and waits for completion. For interactive mode, the runner needs to:

1. Spawn the agent as before
2. When agent responds (but hasn't called `signal_ready`), surface the response
3. Wait for user input
4. Send input as a new user message to the agent
5. Repeat until `signal_ready` is called

The key change is in `handle_info({:agent_done, ...})` — for interactive steps, "done" means "ready for user input", not "step complete". The agent should only call `signal_ready` when it has enough information to produce the final output.

### CLI Interactive Loop

The CLI needs to become interactive when running a planning workflow. The flow:

```
$ fam plan "Add user authentication"
[research step runs autonomously...]

Analyst: I have some questions about the authentication approach:
1. Do you want session-based or token-based auth?
2. What OAuth providers should be supported?

> session-based, Google and GitHub

Analyst: Got it. Here's the draft specification...
[continues until signal_ready]

[review-spec step runs autonomously...]

Review complete. Specification saved to .familiar/specs/user-auth.md
```

### Conversation Scope

AgentProcess already creates conversations with `scope: "agent"`. For planning workflows, use `scope: "planning"` so `--resume` can find them. Thread this from the CLI command through WorkflowRunner opts to AgentProcess.

### Resume Architecture

Resume requires reconstructing workflow state from a conversation. The conversation stores all messages. WorkflowRunner needs a `resume/2` function that:
1. Loads the conversation
2. Determines which step was active (from conversation context or metadata)
3. Reconstructs the agent with conversation history
4. Continues the interactive loop

### Existing Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| `mode: interactive` in Step struct | Parsed, unused | WorkflowRunner.build_step/1 |
| Conversation persistence | Working | AgentProcess creates and persists |
| `Conversations.latest_active/1` | Working | Supports scope filter |
| `--resume`/`--session` flag parsing | Working | parse_args already handles them |
| `signal_ready` tool | Working | Agents can signal step completion |
| `input_fn` DI pattern | Established | Used in backup restore confirmation |

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/knowledge/default_files.ex` | Add `mode: interactive` to draft-spec step |
| `familiar/lib/familiar/execution/workflow_runner.ex` | Interactive step loop, resume, input_fn DI |
| `familiar/lib/familiar/cli/main.ex` | Wire --resume/--session flags, interactive CLI loop |
| `familiar/lib/familiar/execution/agent_process.ex` | Accept scope option for conversation creation |
| `familiar/test/familiar/execution/workflow_runner_test.exs` | Interactive mode tests |
| `familiar/test/familiar/cli/workflow_commands_test.exs` | Resume/session tests |

### References

- [Source: familiar/lib/familiar/execution/workflow_runner.ex:54] — Step mode field
- [Source: familiar/lib/familiar/execution/workflow_runner.ex:491] — mode parsing
- [Source: familiar/lib/familiar/execution/agent_process.ex:101-126] — conversation creation
- [Source: familiar/lib/familiar/conversations/conversations.ex:42-59] — latest_active/1
- [Source: familiar/lib/familiar/cli/main.ex:49-51] — --resume/--session flag parsing
- [Source: _bmad-output/planning-artifacts/architecture.md:1514-1589] — Decision A3

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Added `mode: interactive` to draft-spec step in feature-planning workflow
- AgentProcess: new `:mode` and `:scope` options; interactive mode enters `:waiting_input` state instead of completing, handles `{:user_message, text}` cast to continue conversation, pauses timeout while waiting
- WorkflowRunner: passes mode/scope to agents, handles `{:agent_needs_input, ...}` and `{:user_input, ...}` message chain, `do_await/4` interactive loop with `input_fn`, stops agent after `signal_ready` to prevent tool-call loops
- CLI: `--resume` and `--session` flags dispatch to `resume_planning/2` which loads conversation messages as context for a new workflow run
- Scope threading: CLI passes `scope: "planning"` → WorkflowRunner → AgentProcess → Conversations.create
- Fixed signal_ready + tool-call loop: WorkflowRunner now stops the agent process after signal_ready completes the step
- Fixed test flake: `ensure_signal_ready_registered()` before interactive tests prevents tool_registry_test from deregistering signal_ready
- 995 tests + 8 properties, 0 failures. Credo strict: 0 issues.

### File List

- `familiar/lib/familiar/knowledge/default_files.ex` — added `mode: interactive` to draft-spec step
- `familiar/lib/familiar/execution/agent_process.ex` — interactive mode, scope option, waiting_input state
- `familiar/lib/familiar/execution/workflow_runner.ex` — interactive message chain, input_fn, agent stop on signal_ready
- `familiar/lib/familiar/cli/main.ex` — --resume/--session flags, resume_planning, scope/input_fn threading
- `familiar/test/familiar/execution/workflow_runner_test.exs` — 3 interactive mode tests, updated default workflow tests
- `familiar/test/familiar/cli/workflow_commands_test.exs` — 5 resume/session tests
- `familiar/test/familiar/knowledge/default_files_test.exs` — interactive mode parsing test
