# Story 5.8: Workflow Runner

Status: review

## Story

As a developer building the harness,
I want a module that reads workflow markdown definitions and sequences agents through steps,
So that planning, implementation, fix, and custom workflows all execute through one mechanism.

## Acceptance Criteria

### AC1: Workflow Parsing

**Given** a workflow markdown file with YAML frontmatter
**When** `WorkflowRunner.parse/1` is called with the file path
**Then** it parses the YAML frontmatter and extracts the workflow definition
**And** returns `{:ok, %Workflow{name, description, steps: [%Step{}]}}`
**And** each step has: `name`, `role`, `mode` (`:autonomous` or `:interactive`, default `:autonomous`), `input` (list), `output` (string)
**And** returns `{:error, reason}` for missing/invalid files or malformed YAML

### AC2: Sequential Step Execution

**Given** a parsed workflow with sequential steps
**When** `WorkflowRunner.run/2` is called with the workflow and initial context
**Then** steps execute in order — each step spawns an `AgentProcess` via `AgentSupervisor`
**And** the runner waits for each agent to complete (receives `{:agent_done, id, result}`)
**And** the agent's result is stored as the step's output
**And** the next step receives accumulated context from all previous steps
**And** the workflow completes when all steps finish, returning `{:ok, %{steps: results}}`

### AC3: Context Accumulation

**Given** a multi-step workflow
**When** step N completes with output
**Then** step N+1 receives `%{previous_steps: [%{step: name, output: result}, ...]}`
**And** the context is injected into the agent's task description
**And** steps can reference specific prior outputs via the `input` field in their definition

### AC4: `signal_ready` Tool Implementation

**Given** the workflow runner is managing an agent step
**When** the agent calls the `:signal_ready` tool
**Then** the tool sends a message to the workflow runner process
**And** the workflow runner treats this as step completion (equivalent to agent finishing)
**And** the tool returns `{:ok, %{status: "acknowledged"}}` to the agent
**And** if no workflow runner is managing the agent, the tool returns `{:ok, %{status: "no_workflow"}}` (noop)

### AC5: Step Failure Handling

**Given** a workflow is running
**When** a step's agent fails (crashes, timeout, max tool calls exceeded)
**Then** the workflow stops and returns `{:error, {:step_failed, %{step: name, reason: reason}}}`
**And** the failure is logged
**And** subsequent steps are not executed

### AC6: Workflow Runner as GenServer

**Given** the workflow runner
**When** it starts
**Then** it is a GenServer process (not supervised globally — started per-workflow)
**And** it tracks workflow state: `:pending`, `:running`, `:completed`, `:failed`
**And** it is the parent of all spawned agent processes (receives `:agent_done` messages)
**And** callers can query status via `WorkflowRunner.status/1`

### AC7: Harness Core Integration

**Given** the workflow runner is implemented
**When** it is added to the codebase
**Then** it is part of the `Familiar.Execution` boundary (harness core, NOT an extension)
**And** it is exported from the boundary
**And** the `signal_ready` tool is implemented as a real tool (replacing the builtin stub)

### AC8: Test Coverage

**Given** `Familiar.Execution.WorkflowRunner` is implemented
**When** `mix test` runs
**Then** tests cover: parsing (valid workflow, invalid file, malformed YAML), sequential execution (single step, multi-step), context accumulation, signal_ready tool, step failure handling, workflow state management
**And** tests mock LLM to produce deterministic tool calls and completions
**And** Credo strict passes with 0 issues
**And** no regressions in existing test suite (855 tests + 5 properties baseline)

## Tasks / Subtasks

- [x] Task 1: Define workflow data structures (AC: 1)
  - [x] Create `Familiar.Execution.WorkflowRunner` module
  - [x] Define `%Workflow{name, description, steps}` struct
  - [x] Define `%Step{name, role, mode, input, output}` struct
  - [x] `mode` defaults to `:autonomous`, `input` defaults to `[]`

- [x] Task 2: Implement workflow parsing (AC: 1)
  - [x] `parse/1` — reads file, splits YAML frontmatter, parses with `YamlElixir`
  - [x] Extract `name`, `description`, `steps` from YAML
  - [x] Convert each step map to `%Step{}` struct
  - [x] Handle errors: file not found, invalid YAML, missing required fields

- [x] Task 3: Implement WorkflowRunner GenServer (AC: 2, 5, 6)
  - [x] `start_link/1` with opts: `:workflow`, `:context`, `:caller`, `:familiar_dir`, `:supervisor`
  - [x] State tracks workflow, context, status, step index, results, caller, agent pid/ref
  - [x] `init/1` — set status `:pending`
  - [x] `run/1` (cast) — begin execution, set status `:running`, start first step
  - [x] `status/1` — return current state summary

- [x] Task 4: Step execution loop (AC: 2, 3)
  - [x] `start_next_step/1` — spawn AgentProcess via configurable supervisor
  - [x] Build task description with context from previous steps
  - [x] `handle_info({:agent_done, id, result})` — store result, advance or complete
  - [x] Notify caller with `{:workflow_done, pid, result}` on completion

- [x] Task 5: Context accumulation (AC: 3)
  - [x] Build `%{previous_steps: [%{step: name, output: result}]}` from completed steps
  - [x] Format as text block in task description
  - [x] Support `input` field — filter context to only named prior outputs
  - [x] Truncate long outputs (500 chars)

- [x] Task 6: Implement `signal_ready` tool (AC: 4)
  - [x] `register_signal_ready_tool/0` registers real implementation with ToolRegistry
  - [x] Tool looks up runner via ETS registry (`agent_id → runner_pid`)
  - [x] Sends `{:signal_ready, agent_id}` to runner
  - [x] Runner treats signal_ready as step completion
  - [x] Returns `{:ok, %{status: "no_workflow"}}` when no runner found

- [x] Task 7: Step failure handling (AC: 5)
  - [x] `handle_info({:agent_done, id, {:error, reason}})` — set status `:failed`, notify caller
  - [x] `Process.monitor/1` + `handle_info({:DOWN, ...})` for agent crashes
  - [x] Log failure with step name and reason

- [x] Task 8: Convenience API (AC: 6)
  - [x] `run_workflow/3` — parse + start + run, blocks until complete
  - [x] `run_workflow_parsed/3` — run pre-parsed workflow
  - [x] `await_completion/1` — monitors runner, receives `{:workflow_done, ...}`

- [x] Task 9: Update boundary exports and AgentProcess fix (AC: 7)
  - [x] Add `WorkflowRunner` to `Familiar.Execution` boundary exports
  - [x] `AgentSupervisor.start_agent/1` accepts `:supervisor` opt for test isolation
  - [x] `AgentProcess` changed to `restart: :temporary` (one-shot agents shouldn't restart)
  - [x] `signal_ready` tool registered in `application.ex` after builtins

- [x] Task 10: Tests (AC: 8)
  - [x] Create `test/familiar/execution/workflow_runner_test.exs`
  - [x] Test: parse valid workflow file (steps, modes, inputs)
  - [x] Test: parse missing file, malformed YAML, missing name, missing steps, missing role
  - [x] Test: single-step workflow executes and completes
  - [x] Test: multi-step workflow executes in sequence
  - [x] Test: context accumulation — previous output appears in next step's task
  - [x] Test: input field filters to named prior outputs
  - [x] Test: step failure stops workflow
  - [x] Test: multi-step stops on first failure
  - [x] Test: signal_ready acknowledged when runner exists
  - [x] Test: signal_ready no_workflow when no runner
  - [x] Test: status returns pending before run
  - [x] Test: run_workflow convenience from file
  - [x] Test: run_workflow parse error
  - [x] Each test gets isolated DynamicSupervisor via `start_supervised!`

- [x] Task 11: Credo, formatting, full regression (AC: 8)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (871 tests + 5 properties)

## Dev Notes

### Architecture Constraints

- **Harness core, NOT an extension** — WorkflowRunner is infrastructure like AgentProcess and ToolRegistry. It does NOT implement the Extension behaviour. [Source: architecture.md line 1827]
- **GenServer per workflow** — Each workflow run is a separate GenServer process. Not globally supervised — started on demand by callers (CLI, web, tests). [Source: architecture.md line 1553-1557]
- **Markdown workflow files** — Workflows defined in `.familiar/workflows/*.md` with YAML frontmatter. No Elixir code changes to create new workflows. [Source: architecture.md line 1520-1550]
- **`yaml_elixir`** — Already a dependency in `mix.exs` (`~> 2.9`). Use `YamlElixir.read_from_string/1` for frontmatter parsing.

### AgentProcess Integration

The workflow runner spawns agents via:
```elixir
AgentSupervisor.start_agent(
  role: step.role,
  task: build_task_description(step, context),
  parent: self()  # workflow runner receives {:agent_done, id, result}
)
```

Agent completion is signaled via:
```elixir
# In AgentProcess — already implemented:
send(parent, {:agent_done, agent_id, {:ok, content}})
send(parent, {:agent_done, agent_id, {:error, reason}})
```

### signal_ready Tool Implementation

The `signal_ready` tool needs to find its managing workflow runner. Strategy: use `context.agent_id` to look up the runner. The workflow runner stores a mapping of `agent_id → runner_pid` in a registry (simple Agent or ETS).

```elixir
# In signal_ready tool:
def signal_ready(_args, context) do
  agent_id = context[:agent_id]
  case WorkflowRunner.find_runner(agent_id) do
    {:ok, runner_pid} ->
      send(runner_pid, {:signal_ready, agent_id})
      {:ok, %{status: "acknowledged"}}
    :error ->
      {:ok, %{status: "no_workflow"}}
  end
end
```

Use a named ETS table or `Registry` to track `{agent_id → runner_pid}` mappings. Created by the workflow runner, cleaned up on completion.

### Workflow YAML Format

```yaml
name: feature-planning
description: Plan a new feature
steps:
  - name: analyze
    role: analyst
    mode: interactive
  - name: research
    role: librarian
    mode: autonomous
    input: [analyze]
  - name: write_spec
    role: spec-writer
    mode: autonomous
    input: [analyze, research]
```

Parsed into:
```elixir
%Workflow{
  name: "feature-planning",
  description: "Plan a new feature",
  steps: [
    %Step{name: "analyze", role: "analyst", mode: :interactive, input: [], output: nil},
    %Step{name: "research", role: "librarian", mode: :autonomous, input: ["analyze"], output: nil},
    %Step{name: "write_spec", role: "spec-writer", mode: :autonomous, input: ["analyze", "research"], output: nil}
  ]
}
```

### Context Accumulation Format

```elixir
# After step "analyze" completes with "Analysis results..."
context = %{
  previous_steps: [
    %{step: "analyze", output: "Analysis results..."}
  ]
}

# Task description for "research" step:
"""
[Workflow: feature-planning — Step: research]

Previous step results:
- analyze: Analysis results...

Your task: <original task or role instructions>
"""
```

### Test Strategy

Tests mock the LLM to return predetermined responses:
```elixir
# Agent completes immediately with a result
Familiar.Providers.LLMMock
|> expect(:chat, fn messages, _opts ->
  {:ok, %{content: "Step result from agent"}}
end)
```

For signal_ready tests, mock LLM to return a tool call:
```elixir
Familiar.Providers.LLMMock
|> expect(:chat, fn _messages, _opts ->
  {:ok, %{content: "", tool_calls: [%{name: "signal_ready", arguments: %{}}]}}
end)
```

Use temp directories for workflow files. Create minimal workflow YAML for each test case.

### Existing Patterns to Follow

- **GenServer pattern**: See `AgentProcess` — start_link, init, handle_info, handle_call
- **Agent spawning**: See `AgentSupervisor.start_agent/1`
- **Parent notification**: See `AgentProcess.notify_parent/2` — `send(pid, {:agent_done, id, result})`
- **YAML parsing**: `YamlElixir.read_from_string/1` for frontmatter extraction
- **Boundary exports**: Add to `Familiar.Execution` exports in `execution.ex`

### Previous Story Intelligence (Story 5.7)

- Extension pattern works well for thin wrappers but WorkflowRunner is core, not extension
- `put_if_present` with `is_nil` check (from review) — good pattern for optional fields
- Event handlers should be fire-and-forget when calling into async work
- Test baseline: 855 tests + 5 properties, 0 failures
- Credo strict: 0 issues

### Deferred Items (NOT in scope)

- **Interactive mode** — Architecture describes multi-turn conversation via Channel. Requires Channel/LiveView integration. For this story, interactive steps run the same as autonomous (agent executes to completion). Interactive mode deferred to Epic 6 (CLI/UI integration).
- **Parallel execution** — Architecture says `parallel: true` honored in MVP. Adds significant complexity (dependency graph, max_parallel_agents config). Deferred to a follow-up story or 5.10 prep.
- **Workflow-level hooks** — `on_workflow_complete` event hook mentioned in architecture. Not in MVP hook list. Defer.
- **File conflict prevention** — PM role checks intended files against running workers. This is agent-level logic, not workflow runner responsibility.
- **TOML config** — `[execution] max_parallel_agents` config. No TOML parser. Opts for now.

### Project Structure Notes

New files:
```
lib/familiar/execution/
├── workflow_runner.ex      # NEW — WorkflowRunner GenServer

test/familiar/execution/
├── workflow_runner_test.exs  # NEW — Workflow runner tests
```

Modified files:
```
lib/familiar/execution/execution.ex   # MODIFIED — add WorkflowRunner to boundary exports
lib/familiar/execution/tool_registry.ex  # MODIFIED — implement signal_ready tool (or register via runner)
```

### References

- [Source: architecture.md line 1553-1557 — Workflow runner behavior]
- [Source: architecture.md line 1520-1550 — Workflow YAML format]
- [Source: architecture.md line 1424 — signal_ready tool]
- [Source: architecture.md line 1827 — WorkflowRunner is harness core]
- [Source: architecture.md line 1083 — Planning is a workflow, not a special system]
- [Source: epics.md line 1314-1321 — Story 5.8 scope]
- [Source: agent_process.ex — notify_parent, {:agent_done, id, result}]
- [Source: agent_supervisor.ex — start_agent/1]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- WorkflowRunner GenServer that parses YAML workflow definitions and sequences agents through steps
- Workflow/Step structs with YAML frontmatter parsing (reuses `YamlElixir`, same pattern as role loader)
- Sequential step execution: spawn AgentProcess per step, wait for `{:agent_done}`, accumulate context
- Context accumulation: previous step outputs injected into next step's task description, `input` field filters
- `signal_ready` tool implementation: ETS registry maps agent_id → runner_pid, runner treats as step completion
- `run_workflow/3` and `run_workflow_parsed/3` convenience APIs that block until workflow completes
- `AgentSupervisor.start_agent/1` now accepts `:supervisor` opt for test isolation
- **AgentProcess changed to `restart: :temporary`** — agents are one-shot tasks, should not restart on crash (was `:permanent`, caused DynamicSupervisor to restart dead agents consuming mock responses in tests)
- Step failure handling via `{:agent_done, _, {:error, _}}` and `Process.monitor` for crashes
- Tests use per-test isolated DynamicSupervisor via `start_supervised!` to prevent cross-test agent leaks
- LLM mock uses role-based response routing (system prompt content → deterministic response) instead of fragile counters
- Credo strict: 0 issues
- 16 new tests; 871 total tests + 5 properties, 0 failures, 0 regressions

### File List

- `familiar/lib/familiar/execution/workflow_runner.ex` — NEW: WorkflowRunner GenServer with parsing, execution, signal_ready
- `familiar/test/familiar/execution/workflow_runner_test.exs` — NEW: 16 workflow runner tests
- `familiar/lib/familiar/execution/agent_process.ex` — MODIFIED: `restart: :temporary`
- `familiar/lib/familiar/execution/agent_supervisor.ex` — MODIFIED: `:supervisor` opt in `start_agent/1`
- `familiar/lib/familiar/execution/execution.ex` — MODIFIED: add WorkflowRunner to boundary exports
- `familiar/lib/familiar/application.ex` — MODIFIED: register signal_ready tool after builtins
