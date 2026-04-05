# Story 6.1: Default Role and Skill Refinement

Status: done

## Story

As a user initializing Familiar on a project,
I want the default role and skill files to have correct YAML frontmatter and tool references that match the actual tool registry,
so that agents work out of the box without manual file editing.

## Context

The default role and skill files were created in Epic 4.5 (Story 4.5-2) before the harness was built. They reference tools that may not match the actual ToolRegistry builtin names (e.g., `run_shell` vs `run_command`). The workflow files are plain markdown stubs without the YAML frontmatter format that WorkflowRunner expects. This story aligns all default files with the harness as it actually exists.

## Acceptance Criteria

### AC1: Role Files Have Correct Tool References

**Given** the default role files installed by `DefaultFiles.install/1`
**When** an agent loads a role and its referenced skills
**Then** all tool names in skill files match registered builtin tools in ToolRegistry
**And** no agent fails due to "unknown tool" errors from stale references

### AC2: Workflow Files Have WorkflowRunner-Compatible Frontmatter

**Given** the default workflow files (`feature-planning.md`, `feature-implementation.md`, `task-fix.md`)
**When** WorkflowRunner parses them
**Then** each has valid YAML frontmatter with `name`, `description`, `steps` fields
**And** each step has `name`, `agent` (role name), and `instruction` fields

### AC3: Skill Tool Names Match ToolRegistry Builtins

**Given** the default skill files reference tools by name
**When** compared against `ToolRegistry.builtin_tools/0`
**Then** every tool reference is a valid registered tool name
**And** `run_shell` → `run_command`, `search_context` / `store_context` stay as-is (registered by KnowledgeStore extension)

### AC4: DefaultFiles.install/1 Still Works

**Given** the updated file contents in `default_files.ex`
**When** `DefaultFiles.install/1` is called
**Then** all files are written to the correct directories
**And** existing files are not overwritten
**And** the install function returns `:ok`

### AC5: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: Audit and fix skill tool references (AC: 1, 3)
  - [x] Fixed `run_shell` → `run_command` in implement.md and test.md
  - [x] Updated `@mvp_tools` in validator.ex to include all builtin + extension tools
  - [x] All other tool references verified correct

- [x] Task 2: Update workflow files with WorkflowRunner frontmatter (AC: 2)
  - [x] Added YAML frontmatter to all 3 workflows with `name`, `description`, `steps`
  - [x] Each step has `name` and `role` (WorkflowRunner requires `role`, not `agent`)
  - [x] Step roles reference valid default roles (analyst, coder, reviewer)

- [x] Task 3: Add test validating tool name consistency (AC: 1, 3, 4)
  - [x] Added test: all skill tool references are valid registered tool names
  - [x] Added tests: workflow files have valid YAML frontmatter, step roles reference valid roles
  - [x] Consolidated stale warning tests (all tools now in MVP list, no warnings expected)
  - [x] Removed "default debounce is 500ms" test (testing a constant)
  - [x] Added `notify_ready` DI to FileWatcher for test readiness signaling

## Dev Notes

### WorkflowRunner Step Format

From `familiar/lib/familiar/execution/workflow_runner.ex`, the expected YAML frontmatter format for workflows is:

```yaml
---
name: feature-planning
description: Plan a new feature from description to approved spec
steps:
  - name: research
    agent: analyst
    instruction: Research existing code and knowledge store for context
  - name: draft-spec
    agent: analyst
    instruction: Draft a specification with acceptance criteria
  - name: review
    agent: reviewer
    instruction: Review the specification for completeness
---
```

### Current Tool Registry Builtins (11 tools)

`read_file`, `write_file`, `delete_file`, `list_files`, `search_files`, `run_command`, `spawn_agent`, `run_workflow`, `monitor_agents`, `broadcast_status`, `signal_ready`

Plus extension tools: `search_context`, `store_context` (KnowledgeStore)

### Stale References to Fix

- `implement.md`: `run_shell` → `run_command`
- `test.md`: `run_shell` → `run_command`

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/knowledge/default_files.ex` | Update workflow frontmatter, fix skill tool names |
| `familiar/test/familiar/knowledge/default_files_test.exs` | Add tool name validation test (if file exists, else create) |

### References

- [Source: familiar/lib/familiar/execution/tool_registry.ex:197-216] — builtin_tools list
- [Source: familiar/lib/familiar/execution/workflow_runner.ex] — YAML frontmatter parsing
- [Source: familiar/lib/familiar/knowledge/default_files.ex] — current default file contents

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Fixed `run_shell` → `run_command` in implement.md and test.md skill files
- Updated `@mvp_tools` in validator.ex to include all 14 builtin + extension tools
- Added WorkflowRunner-compatible YAML frontmatter to all 3 default workflow files
- Added 3 new tests: tool name validation, workflow frontmatter validation, workflow role validation
- Consolidated 2 stale warning tests into 1 (all tools now valid, no warnings)
- Removed constant-testing "default debounce is 500ms" test
- Added `notify_ready` option to FileWatcher for test readiness signaling
- Extracted `start_backend/4` from FileWatcher.init to satisfy Credo nesting
- 966 tests + 8 properties. Credo strict: 0 issues.

### File List

- `familiar/lib/familiar/knowledge/default_files.ex` — workflow frontmatter, skill tool name fixes
- `familiar/lib/familiar/roles/validator.ex` — updated `@mvp_tools` list
- `familiar/lib/familiar/execution/file_watcher.ex` — added `notify_ready` option, extracted `start_backend/4`
- `familiar/test/familiar/knowledge/default_files_test.exs` — 3 new tests, consolidated warning tests
- `familiar/test/familiar/execution/file_watcher_test.exs` — use notify_ready, removed constant test
