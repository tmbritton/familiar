# Story 7.2: Role & Skill CLI Commands

Status: done

## Story

As a developer using the `fam` CLI,
I want `fam roles` and `fam skills` commands to list, inspect, and validate the agent configuration files,
so that I can understand and manage the available agent roles and their capabilities.

## Context

The Roles module (`Familiar.Roles`) already provides `list_roles/1`, `list_skills/1`, `load_role/2`, `load_skill/2`, `validate_role/2`, and `validate_skill/2`. These functions are fully implemented and tested. This story exposes them through the CLI following the established command dispatch pattern.

Story 7-1 added the `--role` flag to `fam chat`, confirming the roles infrastructure works end-to-end.

## Acceptance Criteria

### AC1: `fam roles` Lists All Available Roles

**Given** the `.familiar/roles/` directory contains role markdown files
**When** the user runs `fam roles`
**Then** all valid roles are listed with their name, description, and skill count
**And** invalid role files are excluded (not crashed on)

### AC2: `fam roles <name>` Shows Role Details

**Given** a valid role name
**When** the user runs `fam roles analyst`
**Then** the role's name, description, model, lifecycle, skills list, and a prompt preview (first 200 chars) are displayed
**When** the role doesn't exist
**Then** `{:error, {:role_not_found, %{name: "..."}}}` is returned

### AC3: `fam skills` Lists All Available Skills

**Given** the `.familiar/skills/` directory contains skill markdown files
**When** the user runs `fam skills`
**Then** all valid skills are listed with their name, description, and tool count

### AC4: `fam skills <name>` Shows Skill Details

**Given** a valid skill name
**When** the user runs `fam skills implement`
**Then** the skill's name, description, tools list, constraints, and an instructions preview (first 200 chars) are displayed
**When** the skill doesn't exist
**Then** `{:error, {:skill_not_found, %{name: "..."}}}` is returned

### AC5: JSON and Quiet Output Modes

**Given** any roles/skills command
**When** run with `--json`
**Then** the result is output as JSON envelope
**When** run with `--quiet`
**Then** a concise summary is output (e.g., `roles:6` or `role:analyst`)

### AC6: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict and Dialyzer pass with 0 issues

## Tasks / Subtasks

- [x] Task 1: Add `fam roles` and `fam roles <name>` commands (AC: 1, 2)
  - [ ] `run_with_daemon({"roles", [], _}, deps)` calls `Roles.list_roles/1`
  - [ ] `run_with_daemon({"roles", [name | _], _}, deps)` calls `Roles.load_role/2`
  - [ ] DI via `list_roles_fn` and `load_role_fn` in deps
  - [ ] Format list result as `{:ok, %{roles: [%{name, description, skills_count}]}}`
  - [ ] Format detail result as `{:ok, %{role: %{name, description, model, lifecycle, skills, prompt_preview}}}`

- [x] Task 2: Add `fam skills` and `fam skills <name>` commands (AC: 3, 4)
  - [ ] `run_with_daemon({"skills", [], _}, deps)` calls `Roles.list_skills/1`
  - [ ] `run_with_daemon({"skills", [name | _], _}, deps)` calls `Roles.load_skill/2`
  - [ ] DI via `list_skills_fn` and `load_skill_fn` in deps
  - [ ] Format list result as `{:ok, %{skills: [%{name, description, tools_count}]}}`
  - [ ] Format detail result as `{:ok, %{skill: %{name, description, tools, constraints, instructions_preview}}}`

- [x] Task 3: Add text formatters and quiet_summary (AC: 5)
  - [ ] `text_formatter("roles")` for list and detail views
  - [ ] `text_formatter("skills")` for list and detail views
  - [ ] `quiet_summary` clauses for roles/skills results

- [x] Task 4: Update help text (AC: 1-4)
  - [ ] Add roles and skills commands to help_text

- [x] Task 5: Write tests (AC: 1-6)
  - [ ] Test list roles with DI mock
  - [ ] Test role detail with DI mock
  - [ ] Test role not found error
  - [ ] Test list skills with DI mock
  - [ ] Test skill detail with DI mock
  - [ ] Test skill not found error
  - [ ] Test JSON and quiet output modes

- [x] Task 6: Verify test baseline (AC: 6)

## Dev Notes

### Roles Module API

```elixir
Roles.list_roles(familiar_dir: dir) :: {:ok, [%Role{name, description, model, lifecycle, skills, system_prompt}]}
Roles.load_role("analyst", familiar_dir: dir) :: {:ok, %Role{}} | {:error, {:role_not_found, %{name: "analyst"}}}
Roles.list_skills(familiar_dir: dir) :: {:ok, [%Skill{name, description, tools, constraints, instructions}]}
Roles.load_skill("implement", familiar_dir: dir) :: {:ok, %Skill{}} | {:error, {:skill_not_found, %{name: "implement"}}}
```

### Output Format Examples

**`fam roles` (text):**
```
Available roles (6):
  analyst        — Planning and requirements analysis (3 skills)
  coder          — Software development and testing (3 skills)
  reviewer       — Code review and quality (1 skill)
  user-manager   — Conversational coordinator (7 skills)
  project-manager — Task orchestration (4 skills)
  librarian      — Knowledge retrieval (2 skills)
```

**`fam roles analyst` (text):**
```
Role: analyst
  Description: Planning and requirements analysis
  Model: default
  Lifecycle: ephemeral
  Skills: research, implement, test
  Prompt: You are a planning analyst who researches...
```

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/cli/main.ex` | Add roles/skills commands, formatters, help text |
| `familiar/lib/familiar/cli/output.ex` | Add quiet_summary clauses |
| `familiar/test/familiar/cli/roles_skills_test.exs` | **New file** — tests |

### References

- [Source: familiar/lib/familiar/roles/roles.ex] — Roles public API
- [Source: familiar/lib/familiar/roles/role.ex] — Role struct
- [Source: familiar/lib/familiar/roles/skill.ex] — Skill struct
- [Source: familiar/lib/familiar/cli/main.ex:200-212] — chat command dispatch pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- `fam roles` lists all roles with name, description, skills count
- `fam roles <name>` shows role details including prompt preview
- `fam skills` lists all skills with name, description, tools count
- `fam skills <name>` shows skill details including instructions preview
- DI via `list_roles_fn`, `load_role_fn`, `list_skills_fn`, `load_skill_fn` in deps
- Text formatters with sorted output and padded columns
- Quiet summary: `roles:N`, `role:name`, `skills:N`, `skill:name`
- Help text updated with roles/skills commands
- 13 new tests, 1038 total, 0 failures. Credo: 0. Dialyzer: 0.

### File List

- `familiar/lib/familiar/cli/main.ex` — roles/skills commands, formatters, help text
- `familiar/lib/familiar/cli/output.ex` — quiet_summary clauses
- `familiar/test/familiar/cli/roles_skills_test.exs` — **new** — 13 tests
