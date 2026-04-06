# Story 7.5: Validate Commands

Status: done

## Story

As a developer using the `fam` CLI,
I want a `fam validate` command that checks all roles, skills, and workflows for correctness,
so that I can catch configuration errors before running agents.

## Context

The validation infrastructure already exists:
- `Roles.validate_role/2` — checks skill cross-references exist on disk
- `Roles.validate_skill/2` — warns on unknown tools (always returns `:ok`)
- `WorkflowRunner.parse/1` — validates workflow YAML syntax and step references
- `Roles.list_roles/1` and `Roles.list_skills/1` — enumerate all files
- `WorkflowRunner.list_workflows/1` — enumerate all workflow files

This story wires a `fam validate` command that runs all validators and reports results.

## Acceptance Criteria

### AC1: `fam validate` Validates Everything

**Given** the `.familiar/` directory with roles, skills, and workflows
**When** the user runs `fam validate`
**Then** all roles are validated (skill cross-references)
**And** all skills are validated (tool references)
**And** all workflows are validated (parse + role references)
**And** a summary is displayed: passed count, warning count, error count

### AC2: `fam validate roles` Validates Only Roles

**Given** valid and invalid role files
**When** the user runs `fam validate roles`
**Then** only roles are validated
**And** each role reports: pass or error with reason

### AC3: `fam validate skills` Validates Only Skills

**Given** skill files with valid and unknown tool references
**When** the user runs `fam validate skills`
**Then** only skills are validated
**And** unknown tools are reported as warnings

### AC4: `fam validate workflows` Validates Only Workflows

**Given** valid and invalid workflow files
**When** the user runs `fam validate workflows`
**Then** only workflows are validated
**And** parse errors and missing role references are reported

### AC5: JSON and Quiet Output Modes

**Given** any validate command
**When** run with `--json` or `--quiet`
**Then** output uses the standard format

### AC6: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict and Dialyzer pass with 0 issues

## Tasks / Subtasks

- [ ] Task 1: Add `fam validate` CLI commands (AC: 1-4)
  - [ ] `run_with_daemon({"validate", [], _}, deps)` — validate all
  - [ ] `run_with_daemon({"validate", ["roles"], _}, deps)` — roles only
  - [ ] `run_with_daemon({"validate", ["skills"], _}, deps)` — skills only
  - [ ] `run_with_daemon({"validate", ["workflows"], _}, deps)` — workflows only
  - [ ] DI via `validate_fn` in deps for testing
  - [ ] Return `{:ok, %{validation: %{roles: [...], skills: [...], workflows: [...], summary: %{passed, warnings, errors}}}}`

- [ ] Task 2: Implement validation logic (AC: 1-4)
  - [ ] `validate_all_roles/1` — list + validate each, collect results
  - [ ] `validate_all_skills/1` — list + validate each, collect results
  - [ ] `validate_all_workflows/1` — list + parse each + check role refs, collect results
  - [ ] Each result: `%{name: name, status: :pass | :warn | :error, message: reason}`

- [ ] Task 3: Add text formatter and quiet_summary (AC: 5)
  - [ ] `text_formatter("validate")` — grouped by type, colored status
  - [ ] `quiet_summary` clause

- [ ] Task 4: Update help text

- [ ] Task 5: Write tests (AC: 1-6)
  - [ ] Test validate all with DI
  - [ ] Test validate roles/skills/workflows individually
  - [ ] Test with passing and failing configs
  - [ ] Test JSON and quiet output

- [ ] Task 6: Verify test baseline (AC: 6)

## Dev Notes

### Validation Result Format

```elixir
{:ok, %{
  validation: %{
    roles: [
      %{name: "analyst", status: :pass},
      %{name: "bad-role", status: :error, message: "references skill 'nonexistent'..."}
    ],
    skills: [
      %{name: "implement", status: :pass},
      %{name: "custom", status: :warn, message: "references unknown tool 'custom_tool'"}
    ],
    workflows: [
      %{name: "feature-planning", status: :pass},
      %{name: "bad-wf", status: :error, message: "missing required field: name"}
    ],
    summary: %{passed: 8, warnings: 1, errors: 1}
  }
}}
```

### Workflow Role Validation

Beyond parsing, check that each workflow step's role exists:
```elixir
for step <- workflow.steps do
  case Roles.load_role(step.role, opts) do
    {:ok, _} -> :pass
    {:error, _} -> {:error, "step '#{step.name}' references unknown role '#{step.role}'"}
  end
end
```

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/cli/main.ex` | Validate commands, formatter, help |
| `familiar/lib/familiar/cli/output.ex` | quiet_summary |
| `familiar/test/familiar/cli/validate_test.exs` | **New file** — tests |

### References

- [Source: familiar/lib/familiar/roles/validator.ex] — validate_role/2, validate_skill/2
- [Source: familiar/lib/familiar/execution/workflow_runner.ex] — parse/1, list_workflows/1
- [Source: familiar/lib/familiar/roles/roles.ex:147-167] — validate_role/2, validate_skill/2

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- `fam validate` validates all roles, skills, and workflows in one pass
- `fam validate roles/skills/workflows` validates one category
- Roles: checks skill cross-references exist on disk
- Skills: warns on unknown tool references
- Workflows: parses YAML + checks role references exist
- Summary: passed/warnings/errors counts
- Dialyzer caught 3 dead catch-all patterns (list functions always return {:ok, _})
- 7 new tests, 1069 total, 0 failures. Credo: 0. Dialyzer: 0.

### File List

- `familiar/lib/familiar/cli/main.ex` — validate commands, validation logic, formatter, help
- `familiar/lib/familiar/cli/output.ex` — quiet_summary
- `familiar/test/familiar/cli/validate_test.exs` — **new** — 7 tests
