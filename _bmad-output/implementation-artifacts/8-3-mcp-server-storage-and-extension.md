# Story 8.3: MCP Server Storage & Client Extension

Status: done

## Story

As a Familiar user,
I want MCP server configurations stored durably so CLI-added servers persist across daemon restarts and `config.toml`-declared servers load automatically,
So that I can manage MCP servers the same way Claude Code does while still supporting checked-in project configs.

## Acceptance Criteria

1. **AC1: Migration.** New `mcp_servers` table with columns: `name` (string, unique, not null), `command` (string, not null), `args_json` (text, default `"[]"`), `env_json` (text, default `"{}"`), `disabled` (boolean, default `false`), `read_only` (boolean, default `false`), timestamps (`utc_datetime`). Index on `name` (unique) and `disabled`.

2. **AC2: Ecto Schema.** `Familiar.MCP.Server` schema maps the `mcp_servers` table. Changeset validates:
   - `name` required, format `^[a-z][a-z0-9_-]*$` (safe as tool-name prefix)
   - `name` rejects the reserved `fam_` prefix
   - `name` rejects collisions with built-in `ToolRegistry` entries (checked at changeset validation via a configurable registry lookup)
   - `command` required, non-empty string
   - `args_json` and `env_json` are valid JSON (decoded at validation, stored as strings)
   - `disabled` and `read_only` are booleans

3. **AC3: Context Module.** `Familiar.MCP.Servers` context provides CRUD:
   - `list/0` → `[%Server{}]` (all rows, ordered by name)
   - `get/1` → `{:ok, %Server{}} | {:error, :not_found}` (by name)
   - `create/1` → `{:ok, %Server{}} | {:error, changeset}`
   - `update/2` → `{:ok, %Server{}} | {:error, changeset}`
   - `delete/1` → `{:ok, %Server{}} | {:error, :not_found}`
   - `enable/1` → `{:ok, %Server{}}` (sets disabled=false)
   - `disable/1` → `{:ok, %Server{}}` (sets disabled=true)
   All functions take server name (string) where applicable.

4. **AC4: Config.toml MCP Parsing.** `Familiar.Config` gains an `mcp_servers` field (list of maps). Parses `[[mcp.servers]]` TOML array-of-tables entries with keys: `name`, `command`, `args` (list), `env` (table of strings). Returns parsed entries in the config struct. Env values are NOT expanded at parse time — expansion happens at client launch via `Familiar.Config.expand_env/1`.

5. **AC5: MCPClient Extension.** `Familiar.Extensions.MCPClient` implements `Familiar.Extension`:
   - `name/0` → `"mcp-client"`
   - `tools/0` → `[]` (tools are registered by individual `Client` GenServers, not the extension)
   - `hooks/0` → `[]` (no lifecycle hooks needed)
   - `child_spec/1` → returns a supervisor spec for its own `DynamicSupervisor` (or reuses `Familiar.MCP.ClientSupervisor`)
   - `init/1` → merges DB servers (`Familiar.MCP.Servers.list/0`) with config.toml servers (`Familiar.Config`), starts a `Client` child for each enabled entry. DB entries win on name collision (warning logged). Config errors log warnings and skip the bad entry — they do not crash boot.

6. **AC6: Server Source Tracking.** Each server entry tracked by the extension carries a source marker (`:db` or `:config`). The extension's `server_status/0` function returns a list of `%{name, source, status, tool_count}` maps for the CLI to consume.

7. **AC7: Reload API.** `MCPClient.reload_server/1` accepts a server name, stops the existing client (if any), re-reads the server config from DB, and starts a fresh `Client` child. Returns `{:ok, pid}` or `{:error, reason}`. This is the entry point for Story 8-4's CLI mutations to trigger live reloads without bouncing the whole extension.

8. **AC8: Read-only Filtering.** When `read_only` is true on a server config, the `Client` registers only tools whose names match a read-only allowlist pattern: `list_*`, `get_*`, `read_*`, `search_*`, `query_*`, `describe_*`, `show_*`, `fetch_*`. Non-matching tools are silently excluded from `ToolRegistry`. This is a capability filter, not a safety veto.

9. **AC9: Reserved Name Validation.** Server names that collide with built-in `ToolRegistry` tool names (checked via `ToolRegistry.list_tools/0`) or start with `fam_` are rejected at creation time with a clear error message.

10. **AC10: Boundary Update.** `Familiar.MCP` boundary exports `Server`, `Servers`, and the `MCPClient` extension module. `deps` includes `Familiar.Execution` (already present) and `Familiar.Extensions`.

11. **AC11: Extension Registration.** `Familiar.Extensions.MCPClient` is added to the extensions list in `config/config.exs`.

12. **AC12: Unit Tests.** Comprehensive tests covering: schema changeset validation (valid/invalid names, reserved prefixes, JSON fields), context CRUD operations, config.toml MCP parsing, extension init with DB+config merge, reload_server lifecycle, read-only filtering, name collision rejection, source tracking.

13. **AC13: Clean Toolchain.** `mix compile --warnings-as-errors`, `mix format`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

14. **AC14: Stress-tested.** Every new test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Create `mcp_servers` migration (AC: 1)
  - [x] New migration file in `priv/repo/migrations/` with timestamp `20260415120000`
  - [x] `create table(:mcp_servers)` with all columns
  - [x] `create unique_index(:mcp_servers, [:name])`
  - [x] `create index(:mcp_servers, [:disabled])`

- [x] Task 2: Create `Familiar.MCP.Server` Ecto schema (AC: 2)
  - [x] New file `lib/familiar/mcp/server.ex`
  - [x] Schema mapping `mcp_servers` table
  - [x] `changeset/2` with all validations: required fields, name format regex, `fam_` prefix rejection, JSON validity for args/env fields
  - [x] `validate_name_not_reserved/1` custom validation that checks `ToolRegistry.list_tools/0` — use DI via app config for testability
  - [x] `@spec` and `@doc` on public functions

- [x] Task 3: Create `Familiar.MCP.Servers` context module (AC: 3)
  - [x] New file `lib/familiar/mcp/servers.ex`
  - [x] CRUD functions: `list/0`, `get/1`, `create/1`, `update/2`, `delete/1`, `enable/1`, `disable/1`
  - [x] All functions return tagged tuples
  - [x] `list/0` orders by name

- [x] Task 4: Add MCP config.toml parsing to `Familiar.Config` (AC: 4)
  - [x] Add `mcp_servers: []` to `Config` struct
  - [x] Parse `parsed["mcp"]["servers"]` (TOML `[[mcp.servers]]`) in `validate_and_build/1`
  - [x] Validate each entry has `name` and `command`; `args` defaults to `[]`, `env` defaults to `%{}`
  - [x] Do NOT expand env vars at parse time

- [x] Task 5: Create `Familiar.Extensions.MCPClient` extension (AC: 5, 6, 7, 8)
  - [x] New file `lib/familiar/extensions/mcp_client.ex`
  - [x] Implement `Familiar.Extension` behaviour
  - [x] `init/1`: merge DB servers + config.toml servers (DB wins on collision, log warning)
  - [x] Start `Client` child for each enabled entry via `ClientSupervisor.start_client/1`
  - [x] `server_status/0`: returns list of `%{name, source, status, tool_count}` maps
  - [x] `reload_server/1`: stop existing client, re-read from DB, start fresh client
  - [x] Read-only filtering: pass `read_only_patterns` to Client opts, Client filters tools after `tools/list`

- [x] Task 6: Integrate read-only filtering in `Familiar.MCP.Client` (AC: 8)
  - [x] Add `read_only` and `read_only_patterns` to Client struct/opts
  - [x] After `tools/list`, filter tools against patterns when `read_only` is true
  - [x] Default patterns: `["list_*", "get_*", "read_*", "search_*", "query_*", "describe_*", "show_*", "fetch_*"]`

- [x] Task 7: Update boundaries and config (AC: 10, 11)
  - [x] Update `Familiar.MCP` boundary exports to include `Server`, `Servers`
  - [x] Update `Familiar.Extensions` boundary if it exists, or verify MCPClient can access MCP context
  - [x] Add `Familiar.Extensions.MCPClient` to extension list in `config/config.exs`

- [x] Task 8: Unit tests (AC: 12)
  - [x] `test/familiar/mcp/server_test.exs` — changeset validations
  - [x] `test/familiar/mcp/servers_test.exs` — CRUD operations (uses `DataCase`)
  - [x] `test/familiar/mcp/config_mcp_test.exs` or inline in existing config tests — config.toml MCP parsing
  - [x] `test/familiar/extensions/mcp_client_test.exs` — extension init, merge logic, reload_server, server_status, read-only filtering

- [x] Task 9: Toolchain verification (AC: 13)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — all pass
  - [x] `mix dialyzer` — 0 errors

- [x] Task 10: Stress test (AC: 14)
  - [x] 50x run on all new test files — 0 flakes

### Review Findings

- [x] [Review][Patch] `validate_json_field/3` does not type-check array vs object — `args_json: "{}"` passes validation [server.ex:78-89]
- [x] [Review][Patch] `validate_name_not_builtin/1` makes live GenServer.call during changeset — wrap in try/rescue fallback [server.ex:61-66]
- [x] [Review][Patch] `parse_mcp_servers/1` hard-fails on first invalid entry instead of warning+skip [config.ex:270-280]
- [x] [Review][Patch] `server_status/0` calls `ToolRegistry.list_tools/0` N times in a loop — call once and pre-group [mcp_client.ex:60-62]
- [x] [Review][Patch] `stop_existing_client/1` doesn't use injected supervisor, always calls global `ClientSupervisor` [mcp_client.ex:241-244]
- [x] [Review][Defer] ETS table ownership — table owned by extension loader process, not a long-lived process; orphan risk on crash — deferred, production init is single-threaded via ExtensionLoader
- [x] [Review][Defer] `reload_server/1` only works for DB-sourced servers; config-sourced servers return `:not_found` — deferred, Story 8-4 scope
- [x] [Review][Defer] `config_entry_to_client_opts/2` hard-codes `read_only: false` for config servers — deferred, config.toml `read_only` field is Story 8-4 `add-json` scope
- [x] [Review][Defer] Read-only filtering test does not assert which tools were actually registered vs filtered — deferred, integration test coverage in Story 8-5
- [x] [Review][Defer] Hardcoded init response IDs 1/2 in Client — deferred, pre-existing from Story 8-2
- [x] [Review][Defer] Duplicate config.toml server names not deduplicated within config source — deferred, edge case for Story 8-4 validation

## Dev Notes

### Two Pieces: Storage + Extension

This story has two distinct layers:

1. **Storage layer** (Tasks 1-4): Ecto schema + context + migration + config parsing. Pure data — no GenServers, no processes.
2. **Extension layer** (Tasks 5-7): `MCPClient` extension that reads from the storage layer and manages `Client` children. This is the bridge between persisted config and running processes.

Build storage first, then extension. The extension depends on the storage layer and the existing `Client`/`ClientSupervisor` from Story 8-2.

### Existing Code to Reuse

| What | Where | How |
|------|-------|-----|
| Client GenServer | `Familiar.MCP.Client` | Story 8-2 — don't modify except for read-only filtering (Task 6) |
| ClientSupervisor | `Familiar.MCP.ClientSupervisor` | Story 8-2 — `start_client/1`, `stop_client/2` already exist |
| Extension behaviour | `Familiar.Extension` | 5 callbacks: `name/0`, `tools/0`, `hooks/0`, `child_spec/1` (optional), `init/1` |
| Extension loading | `Familiar.Execution.ExtensionLoader` | Calls `init/1`, collects tools/hooks/child_specs — already handles failures gracefully |
| KnowledgeStore extension | `Familiar.Extensions.KnowledgeStore` | Reference implementation — copy the pattern |
| Config parsing | `Familiar.Config` | Add `mcp_servers` to struct, parse `parsed["mcp"]["servers"]` in `validate_and_build/1` |
| expand_env | `Familiar.Config.expand_env/1` | Already public (promoted in Story 8-2) — used by Client at launch time |
| ToolRegistry list | `Familiar.Execution.ToolRegistry.list_tools/0` | Returns `[%{name, description, extension}]` — use for name collision check |
| Migration pattern | `priv/repo/migrations/20260410120000_create_workflow_runs.exs` | Follow same style: `create table()`, `add` columns, `create index()` |
| Ecto schema pattern | `Familiar.Execution.WorkflowRuns.Run` | Follow: `schema`, `changeset/2`, `timestamps(type: :utc_datetime)` |

### Config.toml MCP Section

TOML uses `[[mcp.servers]]` (array of tables) for multiple server entries:

```toml
[[mcp.servers]]
name = "github"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "${GITHUB_TOKEN}" }

[[mcp.servers]]
name = "postgres"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-postgres"]
env = { DATABASE_URL = "${DATABASE_URL}" }
```

The `toml` hex library parses `[[mcp.servers]]` into `%{"mcp" => %{"servers" => [%{...}, %{...}]}}`. Access via `parsed["mcp"]["servers"]`. Each entry is a map with string keys.

### Extension Init Flow

The `MCPClient.init/1` function must:

1. Read DB servers: `Familiar.MCP.Servers.list/0`
2. Read config servers: get from application env or load config — the config is already parsed at boot and available via app env or passed in opts
3. Merge: build a map keyed by name. For each config entry, only add if no DB entry with same name exists. Log warning on collisions.
4. For each enabled entry in the merged list, call `ClientSupervisor.start_client/1` with the server's config
5. Track the started clients with their source markers in a module-level Agent or ETS table for `server_status/0`

**Key design decision:** The extension does NOT register tools itself (`tools/0` returns `[]`). Individual `Client` GenServers register their discovered MCP tools directly in `ToolRegistry` — this already works from Story 8-2. The extension is purely a lifecycle manager.

### Extension State Management

The extension needs to track which servers are running and their sources. Options:

1. **ETS table** — simple, queryable, survives extension function calls. Use `ets:new(:mcp_client_servers, [:named_table, :set, :public])` in `init/1`.
2. **GenServer** — heavier than needed since the extension is already loaded by ExtensionLoader.
3. **Module attribute** — won't work, needs mutable state.

Recommended: **ETS table** named `:familiar_mcp_servers`. Rows: `{name, source, client_pid}`. The `server_status/0` function queries ETS, then calls `Client.status/1` on each pid.

### Read-Only Filtering

The read-only filter happens in `Client` after `tools/list` response. Add to `Client`:

```elixir
# In register_discovered_tools/2, before registration:
tools = if state.read_only do
  Enum.filter(tools, fn tool ->
    matches_read_only_pattern?(tool["name"], state.read_only_patterns)
  end)
else
  tools
end
```

Default patterns match prefixes: `list_`, `get_`, `read_`, `search_`, `query_`, `describe_`, `show_`, `fetch_`. Use simple `String.starts_with?/2` matching (the `*` is a glob, not a regex).

### Name Validation

The changeset validation for reserved names needs to call `ToolRegistry.list_tools/0`. To keep the schema testable without starting the registry:

```elixir
# In Server schema:
defp validate_name_not_reserved(changeset) do
  registry = Application.get_env(:familiar, :tool_registry, Familiar.Execution.ToolRegistry)
  name = get_change(changeset, :name)

  if name do
    builtin_names = registry.list_tools() |> Enum.map(& &1.name) |> Enum.map(&to_string/1)
    if name in builtin_names do
      add_error(changeset, :name, "collides with built-in tool '#{name}'")
    else
      changeset
    end
  else
    changeset
  end
end
```

In tests, configure `Application.put_env(:familiar, :tool_registry, FakeToolRegistry)` that returns a known list.

### Boundary Considerations

- `Familiar.MCP` already depends on `Familiar.Execution` (for ToolRegistry). No new boundary dep needed.
- `Familiar.Extensions.MCPClient` lives in the `Familiar.Extensions` boundary, which already depends on `Familiar.Knowledge`. It will need to also access `Familiar.MCP` (for `Servers`, `Client`, `ClientSupervisor`). Check if `Familiar.Extensions` boundary needs a dep on `Familiar.MCP` added.

### Deferred Items from Story 8-2

These deferred items become relevant now:
- `:disabled` status was forward-declared in Client — now it has a real use case (disabled servers should not start clients)
- `:mcp_server_removed` error atom — still Story 8-4 scope (CLI remove command)
- `String.to_atom` on tool names — still deferred, same trust boundary rationale

### Previous Story Intelligence (8-2)

- `port_opener` DI pattern: `{port_ref, send_fn, close_fn}` tuple — the MCPClient extension should pass this through from Client opts
- Client `start_link/1` opts: `:server_name`, `:command`, `:args`, `:env`, `:connect_timeout`, `:call_timeout`, `:port_opener`
- FakePort pattern in tests: GenServer that captures sent data, test helpers `send_line/3` and `send_exit/3` — reuse in extension tests
- `sleep 50ms` after `start_client` in tests to allow `handle_continue` to fire
- Sobelow ignore for `DOS.StringToAtom` already in `.sobelow-conf`
- Credo cyclomatic complexity limit is 9 — extract helpers proactively

### File Structure

```
familiar/
├── lib/familiar/mcp/
│   ├── mcp.ex                # MODIFY — add Server, Servers to exports
│   ├── protocol.ex           # Story 8-1 — don't modify
│   ├── dispatcher.ex         # Story 8-1 — don't modify
│   ├── client.ex             # MODIFY — add read_only filtering
│   ├── client_supervisor.ex  # Story 8-2 — don't modify
│   ├── server.ex             # NEW — Ecto schema
│   └── servers.ex            # NEW — context module (CRUD)
├── lib/familiar/extensions/
│   └── mcp_client.ex         # NEW — Extension implementation
├── lib/familiar/config.ex    # MODIFY — add mcp_servers field + parsing
├── config/config.exs         # MODIFY — add MCPClient to extensions list
├── priv/repo/migrations/
│   └── 20260415120000_create_mcp_servers.exs  # NEW
└── test/
    ├── familiar/mcp/
    │   ├── server_test.exs    # NEW — schema tests
    │   └── servers_test.exs   # NEW — context CRUD tests
    └── familiar/extensions/
        └── mcp_client_test.exs  # NEW — extension tests
```

### Critical Constraints

- **Do NOT modify** `protocol.ex` or `dispatcher.ex` — they are done (Story 8-1).
- **Do NOT modify** `client_supervisor.ex` — it's done (Story 8-2) and its API is sufficient.
- **Do NOT add CLI commands** — that's Story 8-4. This story builds storage + extension only.
- **Do NOT crash on bad config** — config errors log warnings, skip the bad entry, extension stays alive.
- **Env expansion happens at Client launch time**, not at write time or parse time — secrets are never stored literally in the DB (users write `${GITHUB_TOKEN}`, the Client calls `expand_env/1` when opening the Port).
- **ETS table for extension state** — create in `init/1`, query in `server_status/0` and `reload_server/1`. Clean up is automatic (table owned by the process that created it; if extension is reloaded, table is recreated).

### Testing Strategy

**Schema tests** (`server_test.exs`): Pure changeset tests — no DB, no processes. Test valid/invalid names, JSON field validation, reserved prefix rejection, ToolRegistry collision.

**Context tests** (`servers_test.exs`): Use `Familiar.DataCase` for Repo setup. Test CRUD happy paths, uniqueness constraint on name, enable/disable toggling, not_found errors.

**Extension tests** (`mcp_client_test.exs`): Most complex. Need:
- FakePort from Story 8-2's test helpers (or a simpler stub since we're testing the extension, not the client)
- Seed DB with server rows via `Servers.create/1`
- Test init merges DB + config correctly
- Test reload_server lifecycle
- Test server_status returns correct data
- Test read-only filtering (via a client that discovers tools, then check which ones got registered)

For extension tests, use the `port_opener` DI pattern to inject test fakes. The extension passes `port_opener` through to `Client.start_link/1`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 8-3] — Full scope and design decisions
- [Source: _bmad-output/implementation-artifacts/8-2-mcp-client-connection.md] — Previous story patterns and deferred items
- [Source: familiar/lib/familiar/execution/extension.ex] — Extension behaviour definition
- [Source: familiar/lib/familiar/extensions/knowledge_store.ex] — Reference extension implementation
- [Source: familiar/lib/familiar/execution/extension_loader.ex] — Extension loading process
- [Source: familiar/lib/familiar/mcp/client.ex] — Client GenServer (modify for read-only filtering)
- [Source: familiar/lib/familiar/mcp/client_supervisor.ex] — DynamicSupervisor API
- [Source: familiar/lib/familiar/config.ex] — Config struct and TOML parsing
- [Source: familiar/lib/familiar/execution/tool_registry.ex] — ToolRegistry API (list_tools for collision check)
- [Source: familiar/priv/repo/migrations/20260410120000_create_workflow_runs.exs] — Migration pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Created `mcp_servers` migration with unique name index and disabled index
- Created `Familiar.MCP.Server` Ecto schema with changeset validating name format (`^[a-z][a-z0-9_-]*$`), `fam_` prefix rejection, ToolRegistry collision check (via DI), and JSON field validation
- Created `Familiar.MCP.Servers` context module with CRUD: `list/0`, `get/1`, `create/1`, `update/2`, `delete/1`, `enable/1`, `disable/1`
- Added `mcp_servers` field to `Familiar.Config` struct with `[[mcp.servers]]` TOML parsing — validates name+command required, defaults args/env
- Created `Familiar.Extensions.MCPClient` extension implementing `Familiar.Extension` — merges DB + config.toml servers (DB wins on collision), starts Client children via ClientSupervisor, ETS-based tracking
- Extension provides `server_status/0` (returns `%{name, source, status, tool_count}` maps) and `reload_server/1` (stop + re-read from DB + restart)
- Added read-only filtering to `Familiar.MCP.Client` — new `read_only` and `read_only_patterns` fields in struct, filters `tools/list` results via `String.starts_with?/2` matching before registration
- Default read-only patterns: `list_`, `get_`, `read_`, `search_`, `query_`, `describe_`, `show_`, `fetch_`
- Updated `Familiar.MCP` boundary exports to include `Server`, `Servers`
- Updated `Familiar.Extensions` boundary with `Familiar.MCP` dep and `MCPClient` export
- Added `Familiar.Extensions.MCPClient` to extensions list in `config/config.exs`
- Credo nesting fix: extracted `start_or_skip_server/3` helper from `start_enabled_servers/2`
- Ecto.Query import conflict: used `import Ecto.Query, only: [order_by: 2]` to avoid conflict with local `update/2` function
- Fixed `disabled` field not being passed through `server_to_client_opts/3` to `start_enabled_servers/2`
- 22 schema tests, 12 CRUD tests, 5 config tests, 14 extension tests — all pass
- 1337 tests + 16 properties, 0 failures
- 50x stress test: 100/100 clean (50 on new test files, 50 on config tests)

### File List

**New:**
- familiar/priv/repo/migrations/20260415120000_create_mcp_servers.exs
- familiar/lib/familiar/mcp/server.ex
- familiar/lib/familiar/mcp/servers.ex
- familiar/lib/familiar/extensions/mcp_client.ex
- familiar/test/familiar/mcp/server_test.exs
- familiar/test/familiar/mcp/servers_test.exs
- familiar/test/familiar/extensions/mcp_client_test.exs

**Modified:**
- familiar/lib/familiar/config.ex (add mcp_servers field + [[mcp.servers]] parsing)
- familiar/lib/familiar/mcp/client.ex (add read_only filtering)
- familiar/lib/familiar/mcp/mcp.ex (boundary: add Server, Servers exports)
- familiar/lib/familiar/extensions/extensions.ex (boundary: add MCP dep + MCPClient export)
- familiar/config/config.exs (add MCPClient to extensions list)
- familiar/test/familiar/config_test.exs (add MCP config parsing tests)
