# Story 7.3: Workflow & Extension CLI Commands

Status: done

## Story

As a developer using the `fam` CLI,
I want `fam workflows` and `fam extensions` commands to list and inspect workflow definitions and loaded extensions,
so that I can understand the available automation pipelines and what capabilities are active.

## Context

Story 7-2 added `fam roles` and `fam skills` by wiring existing `Roles` module APIs to the CLI. This story follows the same pattern for workflows and extensions.

For workflows, `WorkflowRunner.parse/1` exists but there's no `list_workflows` function — we need to add one that globs `.familiar/workflows/*.md` and parses each file's metadata.

For extensions, `Application.get_env(:familiar, :extensions)` provides the configured modules, and each module implements the `Extension` behaviour with `name/0`, `tools/0`, and `hooks/0` callbacks. `ToolRegistry.list_tools/0` provides tools grouped by extension. No new module is needed — we can query the config and call the callbacks directly.

## Acceptance Criteria

### AC1: `fam workflows` Lists All Available Workflows

**Given** the `.familiar/workflows/` directory contains workflow markdown files
**When** the user runs `fam workflows`
**Then** all valid workflows are listed with their name, description, and step count
**And** invalid workflow files are excluded with a warning

### AC2: `fam workflows <name>` Shows Workflow Details

**Given** a valid workflow name (without `.md` extension)
**When** the user runs `fam workflows feature-planning`
**Then** the workflow's name, description, and steps (with role and mode for each) are displayed
**When** the workflow doesn't exist
**Then** a clear error is returned

### AC3: `fam extensions` Lists Loaded Extensions

**Given** extensions are configured in the application
**When** the user runs `fam extensions`
**Then** each extension is listed with its name and tool count
**And** tools are grouped by extension

### AC4: JSON and Quiet Output Modes

**Given** any workflows/extensions command
**When** run with `--json` or `--quiet`
**Then** output uses the standard format (JSON envelope or concise summary)

### AC5: `list_workflows/1` Function Added to WorkflowRunner

**Given** a `.familiar/workflows/` directory
**When** `WorkflowRunner.list_workflows/1` is called
**Then** it returns `{:ok, [%Workflow{}]}` with all valid parsed workflows
**And** invalid files are silently skipped (logged as warnings)

### AC6: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict and Dialyzer pass with 0 issues

## Tasks / Subtasks

- [ ] Task 1: Add `list_workflows/1` to WorkflowRunner (AC: 5)
  - [ ] Glob `.familiar/workflows/*.md`
  - [ ] Parse each with `parse/1`, collect successes, log failures
  - [ ] Return `{:ok, [%Workflow{}]}`
  - [ ] Add spec and test

- [ ] Task 2: Add `fam workflows` and `fam workflows <name>` commands (AC: 1, 2)
  - [ ] `run_with_daemon({"workflows", [], _}, deps)` calls `list_workflows/1`
  - [ ] `run_with_daemon({"workflows", [name | _], _}, deps)` calls `WorkflowRunner.parse/1`
  - [ ] DI via `list_workflows_fn` and `parse_workflow_fn` in deps
  - [ ] Format list: `{:ok, %{workflows: [%{name, description, step_count}]}}`
  - [ ] Format detail: `{:ok, %{workflow: %{name, description, steps: [%{name, role, mode}]}}}`

- [ ] Task 3: Add `fam extensions` command (AC: 3)
  - [ ] `run_with_daemon({"extensions", [], _}, deps)` queries configured extensions
  - [ ] For each module: call `module.name()`, count tools from `ToolRegistry.list_tools/0`
  - [ ] DI via `list_extensions_fn` in deps
  - [ ] Format: `{:ok, %{extensions: [%{name, tools_count, tools: [tool_names]}]}}`

- [ ] Task 4: Add text formatters and quiet_summary (AC: 4)
  - [ ] `text_formatter("workflows")` for list and detail
  - [ ] `text_formatter("extensions")` for list
  - [ ] `quiet_summary` clauses

- [ ] Task 5: Update help text (AC: 1-3)

- [ ] Task 6: Write tests (AC: 1-6)
  - [ ] Test list_workflows with real files in tmp_dir
  - [ ] Test workflow list/detail CLI commands with DI
  - [ ] Test extensions CLI command with DI
  - [ ] Test JSON and quiet output

- [ ] Task 7: Verify test baseline (AC: 6)

## Dev Notes

### list_workflows/1 Implementation

```elixir
def list_workflows(opts \\ []) do
  familiar_dir = Keyword.get(opts, :familiar_dir, Path.join(File.cwd!(), ".familiar"))
  workflows_dir = Path.join(familiar_dir, "workflows")

  case File.ls(workflows_dir) do
    {:ok, files} ->
      workflows =
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reduce([], fn file, acc ->
          path = Path.join(workflows_dir, file)
          case parse(path) do
            {:ok, wf} -> [wf | acc]
            {:error, reason} ->
              Logger.warning("[WorkflowRunner] Skipping invalid workflow #{file}: #{inspect(reason)}")
              acc
          end
        end)
        |> Enum.reverse()

      {:ok, workflows}

    {:error, :enoent} ->
      {:ok, []}
  end
end
```

### Extensions Query

No new module needed. Query from application config and ToolRegistry:

```elixir
defp list_extensions do
  modules = Application.get_env(:familiar, :extensions, [])
  tools = ToolRegistry.list_tools()

  extensions =
    Enum.map(modules, fn mod ->
      ext_name = mod.name()
      ext_tools = Enum.filter(tools, &(&1.extension == ext_name))
      %{name: ext_name, tools_count: length(ext_tools), tools: Enum.map(ext_tools, & &1.name)}
    end)

  {:ok, %{extensions: extensions}}
end
```

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/execution/workflow_runner.ex` | Add `list_workflows/1` |
| `familiar/lib/familiar/cli/main.ex` | Workflow/extension commands, formatters, help |
| `familiar/lib/familiar/cli/output.ex` | quiet_summary clauses |
| `familiar/test/familiar/cli/workflows_extensions_test.exs` | **New file** — tests |
| `familiar/test/familiar/execution/workflow_runner_test.exs` | Test for `list_workflows/1` |

### References

- [Source: familiar/lib/familiar/execution/workflow_runner.ex:100-106] — parse/1
- [Source: familiar/lib/familiar/execution/tool_registry.ex:57-67] — list_tools/0
- [Source: familiar/lib/familiar/cli/main.ex:369-449] — roles/skills command pattern (Story 7-2)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Added `WorkflowRunner.list_workflows/1` — globs + parses `.familiar/workflows/*.md`, skips invalid
- `fam workflows` lists all workflows with name, description, step count
- `fam workflows <name>` shows details with steps, roles, mode (interactive tagged)
- `fam extensions` lists loaded extensions with tool counts from ToolRegistry
- Text formatters with padded columns, quiet_summary for all result types
- Help text updated
- 10 new tests, 1048 total, 0 failures. Credo: 0. Dialyzer: 0.

### File List

- `familiar/lib/familiar/execution/workflow_runner.ex` — added `list_workflows/1`
- `familiar/lib/familiar/cli/main.ex` — workflows/extensions commands, formatters, help
- `familiar/lib/familiar/cli/output.ex` — quiet_summary clauses
- `familiar/test/familiar/cli/workflows_extensions_test.exs` — **new** — 10 tests
