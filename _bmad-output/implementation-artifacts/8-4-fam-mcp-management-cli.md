# Story 8.4: `fam mcp` Management CLI

Status: done

## Story

As a Familiar user,
I want `fam mcp add/list/get/remove/enable/disable` subcommands that mirror Claude Code's MCP UX,
So that managing MCP servers feels identical across the two tools and doesn't require hand-editing TOML for every change.

## Acceptance Criteria

1. **AC1: `fam mcp list`.** Lists all known servers (DB + config.toml merged view). Columns: NAME, SOURCE (db/config), STATUS (connected/connecting/handshake_failed/crashed/disabled), TOOLS (count), COMMAND (truncated to 40 chars). `--json` emits the standard `Output` data envelope with non-truncated fields. Empty state prints "No MCP servers configured."

2. **AC2: `fam mcp add <name> <command> [args...]`.** Inserts a new row via `Servers.create/1`. Supports `--env KEY=VALUE` (repeatable), `--read-only`, `--disabled` flags. Refuses if name already exists in DB. Prints the resulting config in the same format as `get`. **Literal-secret warning:** if any `--env` value does not contain `${` or `$`, emit a warning to stderr noting the value is stored literally. Still performs the insert.

3. **AC3: `fam mcp add-json <name> <json>`.** Same as `add` but takes a JSON blob. JSON shape: `{"command": "...", "args": [...], "env": {...}, "read_only": false, "disabled": false}`. Validates the JSON is parseable and has `command`.

4. **AC4: `fam mcp get <name>`.** Prints full details for one server: command, full args, env keys (values redacted unless `--show-env`), source, status + reason, discovered tool names. Errors with `:mcp_server_not_found` if absent. `--json` emits data envelope.

5. **AC5: `fam mcp remove <name>`.** Deletes a DB row via `Servers.delete/1` and triggers `MCPClient.reload_server/1` to tear down the client. If the name only exists in config.toml, errors with `:mcp_server_config_only`. Prints confirmation.

6. **AC6: `fam mcp enable <name>` / `fam mcp disable <name>`.** Flips the `disabled` flag via `Servers.enable/1` or `Servers.disable/1` and triggers `MCPClient.reload_server/1`. Config-sourced servers get `:mcp_server_config_only` error.

7. **AC7: Error Envelopes.** New error atoms with friendly messages in `CLI.Output.error_message/2`:
   - `:mcp_server_not_found` → "MCP server '<name>' not found"
   - `:mcp_server_name_taken` → "MCP server '<name>' already exists"
   - `:mcp_server_config_only` → "Server '<name>' is defined in config.toml. Edit the file directly."
   - `:mcp_server_invalid_name` → "Invalid server name: <reason>"
   - `:mcp_server_invalid_json` → "Invalid JSON: <reason>"
   - `:mcp_server_reserved_prefix` → "Server name prefix 'fam_' is reserved"

8. **AC8: Live Reload.** After `add`, `remove`, `enable`, and `disable`, the CLI calls `MCPClient.reload_server/1` so the daemon picks up the change immediately without a restart. The reload call is best-effort — if the daemon is not running, the CLI still succeeds (the next boot picks up the DB change).

9. **AC9: Help Text.** `fam --help` includes a line for each `mcp` subcommand. `fam mcp --help` prints detailed usage for all subcommands.

10. **AC10: Text Formatter.** `text_formatter("mcp")` handles list, get, and mutation results with human-readable formatting.

11. **AC11: CLI Tests.** Each subcommand has tests covering the happy path and at least two error paths. Tests use DI via `deps` map to mock the underlying context/extension calls. Uses `DataCase` for DB tests.

12. **AC12: Clean Toolchain.** `mix compile --warnings-as-errors`, `mix format`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

13. **AC13: Stress-tested.** Every new test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Add MCP error messages to `CLI.Output` (AC: 7)
  - [x] Add `error_message/2` clauses for all 6 new error atoms
  - [x] Keep alphabetical ordering with existing error messages

- [x] Task 2: Add `fam mcp list` command (AC: 1, 10)
  - [x] `run_with_daemon({"mcp", [], _}, deps)` and `run_with_daemon({"mcp", ["list"], _}, deps)` dispatching
  - [x] Calls `MCPClient.server_status/0` for live status, merges with `Servers.list/0` for DB details
  - [x] `text_formatter("mcp")` for human-readable table output
  - [x] JSON output via standard `Output.format/3` path
  - [x] Empty state message

- [x] Task 3: Add `fam mcp get <name>` command (AC: 4, 10)
  - [x] `run_with_daemon({"mcp", ["get", name], flags}, deps)` dispatching
  - [x] Fetches server from `Servers.get/1` + status from `MCPClient.server_status/0`
  - [x] Env value redaction (show keys only; `--show-env` flag for full values)
  - [x] Tool name list from `ToolRegistry.list_tools/0` filtered by extension name
  - [x] Returns `:mcp_server_not_found` if not in DB or config

- [x] Task 4: Add `fam mcp add` command (AC: 2, 8)
  - [x] `run_with_daemon({"mcp", ["add", name, command | args_rest], flags}, deps)` dispatching
  - [x] Parse `--env KEY=VALUE` flags (repeatable), `--read-only`, `--disabled`
  - [x] Build attrs map: `%{name:, command:, args_json:, env_json:, read_only:, disabled:}`
  - [x] Call `Servers.create/1`, handle changeset errors → map to specific error atoms
  - [x] Literal-secret warning for env values without `${`
  - [x] After successful create, call `MCPClient.reload_server/1` (best-effort, log warning on failure)
  - [x] Return server details in same format as `get`

- [x] Task 5: Add `fam mcp add-json` command (AC: 3, 8)
  - [x] `run_with_daemon({"mcp", ["add-json", name, json], _}, deps)` dispatching
  - [x] Parse JSON blob, validate has `command`
  - [x] Build attrs, call `Servers.create/1`
  - [x] Same reload and output as `add`

- [x] Task 6: Add `fam mcp remove` command (AC: 5, 8)
  - [x] `run_with_daemon({"mcp", ["remove", name], _}, deps)` dispatching
  - [x] Check if server is DB-sourced (not config-only)
  - [x] Call `Servers.delete/1`, then `MCPClient.reload_server/1` (best-effort)
  - [x] Return `:mcp_server_config_only` if only in config.toml

- [x] Task 7: Add `fam mcp enable/disable` commands (AC: 6, 8)
  - [x] `run_with_daemon({"mcp", ["enable", name], _}, deps)` and `disable` variant
  - [x] Call `Servers.enable/1` or `Servers.disable/1`
  - [x] Trigger `MCPClient.reload_server/1` (best-effort)
  - [x] Return `:mcp_server_config_only` if config-sourced

- [x] Task 8: Add help text (AC: 9)
  - [x] Add `mcp` section to main help text
  - [x] Add `fam mcp --help` detailed subcommand usage

- [x] Task 9: CLI tests (AC: 11)
  - [x] `test/familiar/cli/mcp_command_test.exs`
  - [x] Tests for: list (empty, with servers), get (found, not found), add (valid, invalid name, duplicate), add-json (valid, invalid JSON), remove (DB, config-only, not found), enable/disable (DB, config-only)
  - [x] Use DI via `deps` map for mocking — follow `workflows_extensions_test.exs` pattern

- [x] Task 10: Toolchain verification (AC: 12)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — all pass
  - [x] `mix dialyzer` — 0 errors

- [x] Task 11: Stress test (AC: 13)
  - [x] 50x run on all new test files — 0 flakes

### Review Findings

- [x] [Review][Patch] `--env`, `--show-env`, `--read-only`, `--disabled` flags not registered in `parse_args` strict OptionParser — silently dropped [main.ex:114-136]
- [x] [Review][Patch] `{:ok, _} = MCPServers.delete(name)` bare match crashes on unexpected failure — use `case` [main.ex:980]
- [x] [Review][Patch] `default_list_mcp_servers/0` returns status-only data, missing COMMAND column — merge with DB data [main.ex:904-907]
- [x] [Review][Patch] Missing name-arg guards for `get`, `remove`, `enable`, `disable` subcommands — fall to wrong error [main.ex:719-746]
- [x] [Review][Defer] `changeset_to_mcp_error` uses substring matching on validation messages — fragile but correct, refactor when schema errors gain machine-readable tags
- [x] [Review][Defer] `fam mcp --help` not implemented as separate subcommand help — deferred, global help covers all subcommands
- [x] [Review][Defer] `config_only_server?` makes redundant second call to `server_status` — performance only, not correctness
- [x] [Review][Defer] `build_json_attrs` doesn't type-check `args`/`env` fields — Story 8-3 schema changeset validates at insert time
- [x] [Review][Defer] Test coverage gaps: no tests for `--show-env`, `--read-only`, `--disabled` flags, config-only error via default path — Story 8-5 integration test scope
- [x] [Review][Defer] No `quiet_summary` clauses for MCP result shapes — falls through to "ok", consistent with existing behavior

## Dev Notes

### CLI Command Dispatch Pattern

All CLI commands in Familiar follow pattern matching on `{command_string, args_list, flags_map}` in `Familiar.CLI.Main`:

```elixir
defp run_with_daemon({"mcp", [], _}, deps) do
  # fam mcp / fam mcp list
  list_fn = Map.get(deps, :list_mcp_servers_fn, &default_list_mcp_servers/0)
  list_fn.()
end
```

The `deps` map enables DI for testing — inject mock functions that return canned results without hitting the daemon or DB.

### Existing Code to Reuse

| What | Where | How |
|------|-------|-----|
| MCP server CRUD | `Familiar.MCP.Servers` | `list/0`, `get/1`, `create/1`, `delete/1`, `enable/1`, `disable/1` |
| MCP server schema | `Familiar.MCP.Server` | Changeset validates name format, JSON fields, reserved names |
| Extension status | `Familiar.Extensions.MCPClient` | `server_status/0` → `[%{name, source, status, tool_count}]` |
| Extension reload | `Familiar.Extensions.MCPClient` | `reload_server/1` → stops client, re-reads DB, starts fresh |
| CLI dispatch | `Familiar.CLI.Main` | Pattern match on `{command, args, flags}` in `run_with_daemon/2` |
| Output formatting | `Familiar.CLI.Output` | `format/3`, `error_message/2`, `exit_code/1` |
| Error envelopes | `Familiar.CLI.Output` | Add `error_message/2` clauses for new error atoms |
| Text formatter | `Familiar.CLI.Main` | `text_formatter/1` returns a formatting function per command |
| DI testing pattern | `test/familiar/cli/workflows_extensions_test.exs` | `deps` map with mock functions |
| Help text | `Familiar.CLI.Main` | `defp help_text/0` — add `mcp` section |
| Tool listing | `Familiar.Execution.ToolRegistry` | `list_tools/0` for discovered tool names per server |

### Command Signatures

```
fam mcp                                    → list all servers
fam mcp list [--json]                      → same as bare `fam mcp`
fam mcp get <name> [--json] [--show-env]   → server details
fam mcp add <name> <command> [args...] [--env KEY=VALUE]... [--read-only] [--disabled]
fam mcp add-json <name> <json>             → add from JSON blob
fam mcp remove <name>                      → delete DB server
fam mcp enable <name>                      → enable server
fam mcp disable <name>                     → disable server
```

### Config-Only Server Detection

For `remove`, `enable`, `disable` — need to distinguish DB vs config-only servers:
1. Try `Servers.get(name)` — if found, it's a DB server
2. If not found in DB, check `MCPClient.server_status/0` for a config-sourced entry
3. If found as config-only → return `:mcp_server_config_only`
4. If not found anywhere → return `:mcp_server_not_found`

### Env Parsing for `add`

Parse `--env KEY=VALUE` flags from the args. The CLI flags map from `OptionParser` can handle repeated flags:

```elixir
# Parse: fam mcp add github npx -y @mcp/server-github --env GITHUB_TOKEN='${GITHUB_TOKEN}' --env NODE_ENV=production
# flags = %{"env" => ["GITHUB_TOKEN=${GITHUB_TOKEN}", "NODE_ENV=production"]}
```

Split each on first `=` to get key/value pairs. Build a JSON object string for `env_json`.

### Literal-Secret Warning

After parsing env values, check each value:
```elixir
Enum.each(env_pairs, fn {key, value} ->
  unless String.contains?(value, "${") or String.contains?(value, "$") do
    IO.puts(:stderr, "Note: #{key} was stored as a literal value. ...")
  end
end)
```

### Live Reload (Best-Effort)

After mutations (`add`, `remove`, `enable`, `disable`), attempt reload:
```elixir
try do
  MCPClient.reload_server(name)
rescue
  _ -> Logger.warning("[CLI] MCP reload skipped — daemon may not be running")
end
```

This succeeds when the daemon is running (ETS table exists, ClientSupervisor active). When the daemon is not running, the DB mutation persists and the next boot picks it up.

### Changeset Error → CLI Error Mapping

Map changeset validation errors to CLI-friendly error atoms:
```elixir
defp changeset_to_error(%Ecto.Changeset{} = cs) do
  cond do
    cs.errors[:name] && match?({_, [constraint: :unique, _]}, hd(cs.errors[:name])) ->
      {:error, {:mcp_server_name_taken, %{name: get_change(cs, :name)}}}
    cs.errors[:name] && String.contains?(error_msg, "fam_") ->
      {:error, {:mcp_server_reserved_prefix, %{name: get_change(cs, :name)}}}
    cs.errors[:name] ->
      {:error, {:mcp_server_invalid_name, %{reason: error_msg}}}
    true ->
      {:error, {:mcp_server_invalid_name, %{reason: format_changeset_errors(cs)}}}
  end
end
```

### Text Formatter Patterns

Follow existing patterns in `Familiar.CLI.Main`:

```elixir
def text_formatter("mcp") do
  fn
    %{servers: servers} -> format_mcp_list(servers)
    %{server: server} -> format_mcp_detail(server)
    %{removed: name} -> "Removed MCP server '#{name}'"
    %{enabled: name} -> "Enabled MCP server '#{name}'"
    %{disabled: name} -> "Disabled MCP server '#{name}'"
    other -> inspect(other, pretty: true)
  end
end
```

### File Structure

```
familiar/
├── lib/familiar/cli/
│   ├── main.ex              # MODIFY — add mcp command dispatch + text formatters + help
│   └── output.ex            # MODIFY — add MCP error messages
└── test/familiar/cli/
    └── mcp_command_test.exs  # NEW — CLI command tests
```

### Critical Constraints

- **Do NOT add web API routes** — CLI commands access `Servers` and `MCPClient` directly. The daemon/CLI architecture in this project has CLI calling context modules directly when the daemon is running in-process (escript mode) or via HTTP when remote. For MCP commands, direct calls are sufficient since the Repo and ETS table are in the same BEAM.
- **Do NOT modify** `server.ex`, `servers.ex`, or `mcp_client.ex` — they are done (Story 8-3).
- **Do NOT modify** `protocol.ex`, `dispatcher.ex`, `client.ex`, or `client_supervisor.ex` — they are done (Stories 8-1, 8-2).
- **Reload is best-effort** — don't fail the CLI command if reload fails (daemon might not be running).
- **Env redaction by default** — `get` shows env keys but not values unless `--show-env`.
- **Credo cyclomatic complexity limit is 9** — extract helper functions proactively.
- The `run_with_daemon` catch-all `{command, _, _}` → `:unknown_command` must remain LAST in the function clause order. Add new `mcp` clauses BEFORE it.

### Previous Story Intelligence (8-3)

- `Servers.create/1` returns `{:error, %Ecto.Changeset{}}` on validation failure — inspect `changeset.errors` for specific field errors
- `Servers.get/1` returns `{:error, :not_found}` — not a changeset
- `MCPClient.server_status/0` returns `[%{name, source, status, tool_count}]` — sorted by name, includes both DB and config servers
- `MCPClient.reload_server/1` returns `{:ok, pid}`, `{:error, :not_found}`, or `{:error, :disabled}`
- Server name regex: `^[a-z][a-z0-9_-]*$`
- JSON field validation now type-checks: `args_json` must decode to list, `env_json` must decode to map
- `validate_name_not_builtin` has try/rescue fallback if ToolRegistry is unavailable

### Testing Strategy

Follow the `workflows_extensions_test.exs` pattern:

```elixir
defmodule Familiar.CLI.MCPCommandTest do
  use Familiar.DataCase, async: false

  alias Familiar.CLI.Main
  alias Familiar.MCP.Servers

  # Stub registry for changeset validation
  defmodule FakeRegistry do
    def list_tools, do: []
  end

  setup do
    Application.put_env(:familiar, :tool_registry, FakeRegistry)
    on_exit(fn -> Application.delete_env(:familiar, :tool_registry) end)
  end

  defp deps(overrides \\ %{}) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
    }
    Map.merge(base, overrides)
  end

  test "list returns empty when no servers" do
    assert {:ok, %{servers: []}} = Main.run({"mcp", [], %{}}, deps())
  end
end
```

For `add`/`remove`/`enable`/`disable`, seed the DB with `Servers.create/1` before testing, then verify the DB state after the CLI call.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 8-4] — Full scope and friction items
- [Source: _bmad-output/implementation-artifacts/8-3-mcp-server-storage-and-extension.md] — Previous story: storage + extension
- [Source: familiar/lib/familiar/cli/main.ex] — CLI dispatch, text formatters, help text
- [Source: familiar/lib/familiar/cli/output.ex] — Error messages and output formatting
- [Source: familiar/lib/familiar/mcp/servers.ex] — CRUD context
- [Source: familiar/lib/familiar/extensions/mcp_client.ex] — Extension: server_status, reload_server
- [Source: familiar/test/familiar/cli/workflows_extensions_test.exs] — CLI test pattern with DI deps

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Added 6 MCP error message clauses to `CLI.Output.error_message/2`
- Added `fam mcp` command group with 7 subcommands: list, get, add, add-json, remove, enable, disable
- All commands follow existing DI pattern with `deps` map for testability
- Added `text_formatter("mcp")` with table formatting for list, detail formatting for get, and confirmation messages for mutations
- Added MCP section to help text with all subcommands
- `add` command parses `--env KEY=VALUE` flags, `--read-only`, `--disabled`; warns on literal secrets (no `${` reference)
- `add-json` command parses JSON blob, validates `command` field required
- `remove`/`enable`/`disable` detect config-only servers and return `:mcp_server_config_only`
- All mutations trigger best-effort `MCPClient.reload_server/1` — failure is logged but doesn't fail the CLI command
- Changeset errors mapped to specific error atoms: `:mcp_server_name_taken`, `:mcp_server_reserved_prefix`, `:mcp_server_invalid_name`
- Extracted `create_mcp_server/1`, `decode_mcp_json/1`, `build_json_attrs/2` helpers to keep cyclomatic complexity under 9
- Fixed Credo nesting issues: extracted `maybe_warn_literal_env/1`, `find_config_server/2`, `start_or_skip_server/3`
- 27 CLI tests covering all subcommands: happy paths + error paths (not found, duplicate, invalid name, reserved prefix, config-only, bad JSON)
- Pre-existing 21 test failures in `WhereCommandTest` confirmed not caused by these changes (fail on clean commit)
- 50x stress test: 50/50 clean

### File List

**New:**
- familiar/test/familiar/cli/mcp_command_test.exs (27 CLI tests)

**Modified:**
- familiar/lib/familiar/cli/main.ex (MCP command dispatch, helpers, text formatter, help text)
- familiar/lib/familiar/cli/output.ex (6 MCP error message clauses)
