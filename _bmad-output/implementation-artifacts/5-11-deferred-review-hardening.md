# Story 5.11: Deferred Review Hardening

Status: done

## Story

As a developer preparing the harness for Phase 3,
I want all deferred code review findings from Epic 5 resolved,
So that we enter Epic 5.5 and workflow development with a clean slate and no accumulated tech debt.

## Acceptance Criteria

### AC1: ETS Safety — No Crashes on Missing or Concurrent Access

**Given** the Safety extension and WorkflowRunner use ETS tables
**When** init is called concurrently or config is read before init
**Then** no crashes occur — defensive guards handle missing tables and concurrent creation

### AC2: Error Handling — No Silent Failures

**Given** various code paths ignore return values or silently drop errors
**When** operations fail
**Then** failures are logged (Logger.warning) rather than silently swallowed

### AC3: Performance — No O(n²) List Operations

**Given** AgentProcess and WorkflowRunner accumulate messages/results
**When** lists grow during execution
**Then** they use prepend-then-reverse rather than repeated `++` append

### AC4: Input Validation — Defensive Boundaries

**Given** user-facing inputs like workflow step references and shell commands
**When** invalid input is provided
**Then** clear errors are returned rather than silent empty results or crashes

### AC5: Resilience — Graceful Degradation

**Given** filesystem operations and process lookups can fail
**When** LocalFileSystem.write can't create directories, or find_runner returns a dead pid
**Then** errors are returned as tuples rather than raised as exceptions

### AC6: Secret Filter Coverage

**Given** the secret filter detects sensitive patterns
**When** scanning for Base64 tokens
**Then** unpadded Base64 strings (no trailing `=`) of sufficient length are also detected

### AC7: Test Baseline

**Given** all fixes are applied
**When** `mix test` runs
**Then** existing tests still pass with 0 failures and 0 regressions
**And** Credo strict passes with 0 issues

## Tasks / Subtasks

- [x] Task 1: ETS hardening (AC: 1)
  - [x] `safety.ex` — atomic try/catch on `:ets.new`, `delete_all_objects` on badarg
  - [x] `safety.ex` — `load_config/0` defensive `ets_get/2` with defaults, handles missing table
  - [x] `workflow_runner.ex` — `ensure_registry/0` implicit try/catch on `:ets.new`

- [x] Task 2: Silent failure fixes (AC: 2)
  - [x] `agent_process.ex` — `log_add_message/1` helper logs warning on error, wraps all 4 call sites
  - [x] `extension_loader.ex` — added catch-all clause for unrecognized hook types with Logger.warning

- [x] Task 3: O(n²) list fixes (AC: 3)
  - [x] `agent_process.ex` — messages stored newest-first, `Enum.reverse` at assembly time
  - [x] `workflow_runner.ex` — step_results stored newest-first, `Enum.reverse` at completion

- [x] Task 4: Input validation (AC: 4)
  - [x] `workflow_runner.ex` — `validate_step_inputs/1` checks all input refs exist during parse
  - [x] `tools.ex` — `search_recursive` takes `depth` param, stops at `@max_search_depth` (10)
  - [x] `tools.ex` — `tokenize_command/1` regex handles single/double quoted arguments

- [x] Task 5: Resilience fixes (AC: 5)
  - [x] `local_file_system.ex` — `File.mkdir_p` (non-bang) returns error tuple on failure
  - [x] `workflow_runner.ex` — `find_runner` checks `Process.alive?` before returning pid

- [x] Task 6: Secret filter improvement (AC: 6)
  - [x] Already addressed — line 22 already has unpadded Base64 pattern with uppercase/+/ lookahead

- [x] Task 7: Formatting, Credo, regression (AC: 7)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (944 tests + 8 properties)

### Review Findings

- [x] [Review][Patch] `format_previous_steps` reversed step_results before formatting for chronological context order
- [x] [Review][Patch] `validate_step_inputs` now rejects self-references and forward references — checks against prior step names only
- [x] [Review][Patch] `tokenize_command` regex handles escaped quotes with `unescape/1` helper
- [x] [Review][Patch] `extension_loader.ex` tools/child_specs now prepend+reverse (matching loaded/failed pattern)
- [x] [Review][Patch] `safety.ex` init nested catch on `delete_all_objects` handles table owned by different process
- [x] [Review][Defer] `search_entry` uses read-failure as directory heuristic — pre-existing design from 5.8.5, unchanged by this diff
- [x] [Review][Defer] `find_runner` TOCTOU race between alive? check and send — inherent in OTP, send to dead pid is silent noop
- [x] [Review][Defer] `load_config` calls `File.cwd!` which can raise — extremely rare edge case, acceptable for MVP
- [x] [Review][Defer] Newest-first message invariant undocumented — documentation task, not a code fix

## Dev Notes

### Architecture Constraints

- **No behavioral changes** — These are defensive hardening fixes. Existing public APIs must not change their success-path behavior.
- **Log, don't crash** — For error paths that were previously silent, add `Logger.warning` rather than raising or changing return types.
- **Prepend+reverse, not ++ append** — Standard Elixir pattern for accumulating lists. Reverse at the point of consumption (prompt assembly for messages, workflow completion for step_results).

### Fix Details

#### ETS Hardening (Task 1)

**Safety init:**
```elixir
# Before (TOCTOU):
if :ets.whereis(@ets_table) != :undefined, do: :ets.delete(@ets_table)
:ets.new(@ets_table, [:set, :protected, :named_table])

# After (atomic):
try do
  :ets.new(@ets_table, [:set, :protected, :named_table])
catch
  :error, :badarg -> :ets.delete_all_objects(@ets_table)
end
```

**Safety load_config:**
```elixir
# Before (crashes if table missing):
[{:project_dir, project_dir}] = :ets.lookup(@ets_table, :project_dir)

# After (returns error if table missing):
case :ets.lookup(@ets_table, :project_dir) do
  [{:project_dir, dir}] -> {:ok, dir}
  [] -> {:error, :not_configured}
end
```

**WorkflowRunner ensure_registry:**
```elixir
# Same pattern as safety — try/catch on :ets.new
```

#### Message Accumulation (Task 3)

AgentProcess stores messages in `state.messages`. Currently appends with `++`. Change to prepend:
- `handle_llm_response`: `messages: [assistant_msg | state.messages]`
- `dispatch_tool_calls`: `messages: Enum.reverse(tool_messages) ++ state.messages` (prepend batch)
- `PromptAssembly.assemble`: receives reversed list, reverses at start

WorkflowRunner stores step results. Prepend during execution, reverse in `complete_workflow`.

#### Search Depth Limit (Task 4)

```elixir
@max_search_depth 10

defp search_recursive(path, pattern, depth \\ 0)
defp search_recursive(_path, _pattern, depth) when depth > @max_search_depth, do: []
defp search_recursive(path, pattern, depth) do
  # ... existing logic, passing depth + 1 to search_entry
end
```

#### Command Parsing (Task 4)

Replace `String.split(command)` with a basic shell-like tokenizer that respects quotes:
```elixir
defp parse_command(command) when is_binary(command) do
  command |> tokenize_command() |> case do
    [executable | args] -> {executable, args}
    [] -> {"", []}
  end
end

defp tokenize_command(cmd) do
  # Split on whitespace, respecting single/double quotes
  ~r/(?:"[^"]*"|'[^']*'|\S+)/
  |> Regex.scan(cmd)
  |> List.flatten()
  |> Enum.map(&String.trim(&1, "\"") |> String.trim("'"))
end
```

#### LocalFileSystem mkdir_p (Task 5)

```elixir
def write(path, content) do
  dir = Path.dirname(path)
  with :ok <- ensure_dir(dir) do
    # existing File.write logic
  end
end

defp ensure_dir(dir) do
  File.mkdir_p(dir)  # non-bang version returns :ok | {:error, posix}
end
```

Note: `File.mkdir_p/1` (non-bang) already returns `:ok | {:error, posix}`. Just switch from `!` to non-bang.

### Previous Story Intelligence (Story 5.10)

- Test baseline: 944 tests + 8 properties, 0 failures
- Credo strict: 0 issues
- AgentProcess now injects `task_id: state.agent_id` into tool context
- Integration tests tagged `@moduletag :integration`, excluded by default

### Excluded Items (Planned for Later Phases)

- Blocking ToolRegistry dispatch → **Epic 5.5 (Async Tool Dispatch)**
- TOCTOU race between parallel agents → **Epic 5.5**
- Hooks mailbox back-pressure → **Epic 5.5**
- `tool_call_id` in messages → **Provider adapter work (post-MVP)**
- Token budget from model config → **Provider adapter work**
- Daemon auth → **Post-MVP**

### Project Structure Notes

Modified files:
```
lib/familiar/extensions/safety.ex              # MODIFIED — ETS hardening
lib/familiar/execution/workflow_runner.ex       # MODIFIED — ETS, O(n²), step.input validation, find_runner
lib/familiar/execution/agent_process.ex         # MODIFIED — add_message logging, O(n²) messages
lib/familiar/execution/extension_loader.ex      # MODIFIED — unrecognized hook type warning
lib/familiar/execution/tools.ex                 # MODIFIED — search depth limit, parse_command quotes
lib/familiar/system/local_file_system.ex        # MODIFIED — mkdir_p non-bang
lib/familiar/knowledge/secret_filter.ex         # MODIFIED — Base64 unpadded pattern
```

No new files.

### References

- [Source: safety.ex:69-73 — ETS init race]
- [Source: safety.ex:181-182 — load_config bare match]
- [Source: workflow_runner.ex:405-411 — ensure_registry TOCTOU]
- [Source: workflow_runner.ex:172-181 — find_runner stale pid]
- [Source: extension_loader.ex:120-131 — hook type case]
- [Source: agent_process.ex:125-126,282,316,321 — add_message + O(n²)]
- [Source: workflow_runner.ex:317 — step_results O(n²)]
- [Source: tools.ex:193 — parse_command String.split]
- [Source: tools.ex:226 — search_recursive no depth limit]
- [Source: workflow_runner.ex:379 — step.input no validation]
- [Source: local_file_system.ex:20 — mkdir_p!]
- [Source: secret_filter.ex:20 — Base64 pattern]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- ETS hardening: Safety + WorkflowRunner both use atomic try/catch on :ets.new instead of check-then-create
- Safety load_config now gracefully handles missing ETS table with defaults
- AgentProcess: log_add_message/1 wraps all Conversations.add_message calls — immediately caught a real silent failure (nil content assistant message)
- ExtensionLoader: unrecognized hook types logged instead of silently ignored
- O(n²) fixed: messages stored newest-first with Enum.reverse at assembly, step_results reversed at completion
- Search depth limited to 10 levels (prevents unbounded recursion on symlink cycles)
- parse_command now handles quoted args via regex tokenizer
- LocalFileSystem.write uses File.mkdir_p (non-bang) — returns error tuple instead of raising
- find_runner checks Process.alive? before returning stale pid
- Workflow parser validates step.input references against known step names
- Secret filter Base64 already addressed (unpadded pattern exists on line 22)
- 944 tests + 8 properties, 0 failures; Credo strict 0 issues

### File List

- `familiar/lib/familiar/extensions/safety.ex` — MODIFIED: ETS init race fix, defensive load_config
- `familiar/lib/familiar/execution/workflow_runner.ex` — MODIFIED: ETS fix, O(n²) fix, step.input validation, find_runner liveness
- `familiar/lib/familiar/execution/agent_process.ex` — MODIFIED: log_add_message, O(n²) messages fix
- `familiar/lib/familiar/execution/extension_loader.ex` — MODIFIED: unrecognized hook type warning
- `familiar/lib/familiar/execution/tools.ex` — MODIFIED: search depth limit, quoted command parsing
- `familiar/lib/familiar/system/local_file_system.ex` — MODIFIED: mkdir_p non-bang
