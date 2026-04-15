# Story 8.5: MCP Client Integration Test

Status: done

## Story

As a developer,
I want an end-to-end test that runs the MCP client against a scripted fake MCP server,
So that a regression in codec, client connection, tool registration, or management CLI shows up before release.

## Acceptance Criteria

1. **AC1: Fake MCP Server.** A test helper module (`FakeServer` or similar) that behaves like a real MCP server subprocess. It receives `initialize` and `tools/list` requests, responds with scripted JSON-RPC 2.0 responses, and can handle `tools/call` requests with configurable responses. Uses the same `FakePort` pattern established in `client_test.exs` and `mcp_client_test.exs`.

2. **AC2: Golden Path — Add, Connect, Call, List, Remove.** Single test flow:
   - Start with no MCP servers configured — extension inits clean
   - `fam mcp add` a server → DB row created, `MCPClient.reload_server/1` starts client
   - Complete handshake (initialize + tools/list) → tools appear in `ToolRegistry`
   - `fam mcp list` shows server with status `:connected` and correct tool count
   - Call a registered tool via `ToolRegistry.dispatch/3` → request round-trips to fake server, response returns
   - `fam mcp remove` the server → DB row deleted, tools unregistered

3. **AC3: Disable/Enable Cycle.** After adding a server with completed handshake:
   - `fam mcp disable` → client tears down, tools disappear from `ToolRegistry`
   - `fam mcp enable` → client restarts, handshake completes, tools reappear

4. **AC4: Config + DB Merge.** Init MCPClient extension with both a config.toml server and a DB server sharing the same name:
   - Warning logged that DB wins on collision
   - `fam mcp list` shows one entry with `source: :db`
   - After removing the DB server, re-init shows config-sourced entry

5. **AC5: Handshake Failure.** Fake server sends malformed or no response to `initialize`:
   - Status transitions to `:handshake_failed` with reason
   - `reload_server/1` retry starts a fresh client that can complete handshake

6. **AC6: Read-Only Filtering.** Add a server with `--read-only` flag:
   - Fake server reports tools: `list_repos`, `get_issue`, `create_issue`, `delete_repo`, `search_code`
   - Only `list_repos`, `get_issue`, `search_code` appear in `ToolRegistry`
   - `create_issue` and `delete_repo` are filtered out

7. **AC7: Literal-Secret Warning.** `fam mcp add --env TOKEN=ghp_xxx` with a non-`${VAR}` value:
   - CLI succeeds (server created)
   - Warning about literal value is emitted (captured via `ExUnit.CaptureIO`)

8. **AC8: CLI Flag Coverage.** Test `--show-env`, `--read-only`, `--disabled` flags via the real CLI parse path (`Main.run/2`):
   - `add` with `--disabled` creates server with `disabled: true`
   - `get` with `--show-env` includes env values in output
   - `add` with `--read-only` creates server with `read_only: true`

9. **AC9: Clean Toolchain.** `mix compile --warnings-as-errors`, `mix format`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

10. **AC10: Stress-tested.** New test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Create test helper for fake MCP server responses (AC: 1)
  - [x] Reuse `FakePort` GenServer pattern from `mcp_client_test.exs`
  - [x] Add `complete_handshake/2` helper that sends initialize + tools/list responses
  - [x] Add `send_tool_response/3` helper for `tools/call` responses
  - [x] Add `send_malformed/2` helper for failure scenarios

- [x] Task 2: Golden path integration test (AC: 2)
  - [x] Init MCPClient extension with empty config
  - [x] CLI `add` via `Main.run/2` with deps containing real `add_mcp_server_fn`
  - [x] Trigger `MCPClient.reload_server/1` with fake port_opener
  - [x] Complete handshake, verify tools in ToolRegistry
  - [x] Dispatch a tool call, verify round-trip
  - [x] CLI `list` verifies `:connected` status
  - [x] CLI `remove`, verify DB empty and tools unregistered

- [x] Task 3: Disable/enable cycle test (AC: 3)
  - [x] Add server, complete handshake, verify tools present
  - [x] Disable via CLI, verify tools gone
  - [x] Enable via CLI, complete new handshake, verify tools back

- [x] Task 4: Config + DB merge test (AC: 4)
  - [x] Create DB server and config entry with same name
  - [x] Init extension, verify DB wins (check ETS source)
  - [x] Verify warning logged via `CaptureLog`

- [x] Task 5: Handshake failure test (AC: 5)
  - [x] Start client where fake server sends error response
  - [x] Verify status is `:handshake_failed`
  - [x] Reload and complete handshake, verify recovery

- [x] Task 6: Read-only filtering test (AC: 6)
  - [x] Add server with `read_only: true`
  - [x] Complete handshake with mixed read/write tools
  - [x] Verify only read-prefixed tools registered
  - [x] Assert specific filtered tools are NOT in ToolRegistry

- [x] Task 7: Literal-secret warning test (AC: 7)
  - [x] `CaptureIO.capture_io(:stderr, ...)` on `fam mcp add --env TOKEN=ghp_xxx`
  - [x] Assert warning contains "literal value" or "stored literally"

- [x] Task 8: CLI flag coverage tests (AC: 8)
  - [x] `add` with `--disabled` → verify `server.disabled == true` in DB
  - [x] `add` with `--read-only` → verify `server.read_only == true` in DB
  - [x] `get` with `--show-env` → verify env values present in result

- [x] Task 9: Toolchain verification (AC: 9)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — all pass (1370 tests, 16 properties, 0 failures)
  - [x] `mix dialyzer` — 0 errors

- [x] Task 10: Stress test (AC: 10)
  - [x] 50x run on new test file — 0 flakes (50/50 clean)

### Review Findings

- [x] [Review][Patch] AC2: Tool-call round-trip via `ToolRegistry.dispatch/3` is missing from golden path test — spec requires dispatching a tool and verifying the request round-trips to the fake server [mcp_integration_test.exs]
- [x] [Review][Patch] AC4: Post-removal re-init showing config-sourced entry is missing — spec requires "After removing the DB server, re-init shows config-sourced entry" [mcp_integration_test.exs]
- [x] [Review][Patch] AC8: `--show-env` test assertion too weak — `detail.env != nil` passes for empty maps; should assert `detail.env["KEY"] == "value"` [mcp_integration_test.exs]
- [x] [Review][Defer] FakePort module duplicated verbatim across 3 test files — extract to `test/support/` when pattern stabilizes
- [x] [Review][Defer] Handshake helpers duplicated across test files — same as FakePort, extract when stable
- [x] [Review][Defer] AC5: No test for malformed JSON (only error response tested) — the error response path validates recovery; malformed JSON is a distinct case but lower priority
- [x] [Review][Defer] `tools/list` error response (id=2 error) not tested at integration level — client transitions to `:connected` with zero tools silently; covered in unit test

## Dev Notes

### Integration Test Architecture

This is an **integration test**, not an E2E test. It exercises real SQLite (via Ecto sandbox), real `MCPClient` extension, real `ToolRegistry`, and real CLI dispatch — but uses a `FakePort` instead of spawning a real subprocess. This matches the pattern in `harness_integration_test.exs` and `workflow_integration_test.exs`.

### Key Modules Under Test

| Module | Role | Real or Mocked |
|--------|------|----------------|
| `Familiar.MCP.Servers` | DB CRUD | Real (Ecto sandbox) |
| `Familiar.Extensions.MCPClient` | Extension lifecycle | Real |
| `Familiar.MCP.Client` | Client GenServer | Real (with FakePort) |
| `Familiar.MCP.ClientSupervisor` | DynamicSupervisor | Test-specific instance |
| `Familiar.Execution.ToolRegistry` | Tool registration | Real (start per-test) |
| `Familiar.CLI.Main` | CLI dispatch | Real |
| Port/subprocess | MCP server process | FakePort (fake) |

### FakePort Pattern (Reuse from Existing Tests)

Both `client_test.exs` and `mcp_client_test.exs` define identical `FakePort` GenServer modules. Reuse the same pattern:

```elixir
defmodule FakePort do
  use GenServer
  def start_link, do: GenServer.start_link(__MODULE__, [])
  def get_sent(port), do: GenServer.call(port, :get_sent)
  def init(_), do: {:ok, %{sent: []}}
  def handle_call(:get_sent, _from, state), do: {:reply, Enum.reverse(state.sent), state}
  def handle_info({:port_data, data}, state), do: {:noreply, %{state | sent: [data | state.sent]}}
  def handle_info(_msg, state), do: {:noreply, state}
end
```

The `port_opener` function wires FakePort into the Client:

```elixir
defp make_port_opener do
  fn _cmd, _args, _env ->
    {:ok, fake_port} = FakePort.start_link()
    send_fn = fn data -> send(fake_port, {:port_data, data}) end
    close_fn = fn -> :ok end
    {fake_port, send_fn, close_fn}
  end
end
```

### Handshake Protocol

The MCP handshake requires two JSON-RPC exchanges:
1. Client sends `initialize` (id=1) → server responds with `protocolVersion`, `capabilities`, `serverInfo`
2. Client sends `tools/list` (id=2) → server responds with `tools` array

After both complete, client status transitions to `:connected`.

```elixir
defp complete_handshake(client, fake_port) do
  init_response = Protocol.encode_response(1, %{
    "protocolVersion" => "2025-11-05",
    "capabilities" => %{"tools" => %{}},
    "serverInfo" => %{"name" => "test-server", "version" => "1.0"}
  })
  send_line(client, fake_port, init_response)

  tools_response = Protocol.encode_response(2, %{
    "tools" => [
      %{"name" => "read_data", "description" => "Read data", "inputSchema" => %{}}
    ]
  })
  send_line(client, fake_port, tools_response)
end

defp send_line(client, fake_port, json) do
  send(client, {fake_port, {:data, {:eol, json}}})
  Process.sleep(50)
end
```

### ToolRegistry Integration

MCP Client registers tools with extension name `"mcp:<server_name>"`. To verify tools are registered:

```elixir
tools = ToolRegistry.list_tools()
mcp_tools = Enum.filter(tools, &(&1.extension == "mcp:my-server"))
assert length(mcp_tools) == expected_count
```

To dispatch a tool call (the round-trip test), the fake server needs to handle the `tools/call` request and respond:

```elixir
# After tool dispatch, the client sends a tools/call request to the fake port
# Check FakePort.get_sent/1 for the outgoing request
# Then send a response back
sent = FakePort.get_sent(fake_port)
# Find the tools/call request, extract its id
call_request = sent |> List.last() |> Jason.decode!()
call_id = call_request["id"]

# Send response
response = Protocol.encode_response(call_id, %{
  "content" => [%{"type" => "text", "text" => "tool result"}]
})
send_line(client, fake_port, response)
```

### CLI Dispatch with Real Deps

For integration tests, use `deps()` with the real default functions (no mock overrides). The CLI will call through to real `Servers.create/1`, `MCPClient.reload_server/1`, etc.

However, `MCPClient.reload_server/1` needs a `port_opener` and `supervisor` injected. The integration test should:
1. Use CLI `Main.run/2` for DB operations (add/remove/enable/disable)
2. Call `MCPClient.reload_server/1` directly with test `port_opener` and `supervisor` opts for the client lifecycle part

This is because the default CLI `reload_server` path uses the production `ClientSupervisor` and real `Port.open`. The integration test injects the test supervisor and fake port opener at the extension/reload level.

### Test Setup Requirements

```elixir
use Familiar.DataCase, async: false

@moduletag :tmp_dir
@moduletag :integration

setup %{tmp_dir: tmp_dir} do
  Application.put_env(:familiar, :tool_registry, FakeRegistry)
  Application.put_env(:familiar, :project_dir, tmp_dir)
  Paths.ensure_familiar_dir!()

  # Start test-specific DynamicSupervisor
  {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

  # Start ToolRegistry for this test
  {:ok, registry} = ToolRegistry.start_link(name: :"test_registry_#{System.unique_integer([:positive])}")

  # Clean ETS between tests
  if :ets.whereis(:familiar_mcp_servers) != :undefined do
    :ets.delete_all_objects(:familiar_mcp_servers)
  end

  on_exit(fn ->
    Application.delete_env(:familiar, :tool_registry)
    Application.delete_env(:familiar, :project_dir)
    try do
      if Process.alive?(sup), do: DynamicSupervisor.stop(sup)
    catch
      :exit, _ -> :ok
    end
    try do
      if Process.alive?(registry), do: GenServer.stop(registry)
    catch
      :exit, _ -> :ok
    end
  end)

  %{supervisor: sup, registry: registry}
end
```

**Important:** ToolRegistry is a named GenServer (`__MODULE__`). The integration test must either:
- Use the global ToolRegistry (if not already started, start it in setup)
- Or start a named instance and ensure MCP Client registers to it

Since `Client` calls `ToolRegistry.register/4` which uses the module name, the integration test should start the global `ToolRegistry` if it's not already running. Use `start_supervised!({ToolRegistry, []})` — but be aware `ToolRegistry` registers itself as `__MODULE__`, so only one test can use it at a time (hence `async: false`).

### Deferred Items This Story Should Cover

From 8-3 code review:
- **Read-only filtering test has no assertion on which tools were registered** — AC6 addresses this explicitly
- **`reload_server/1` only works for DB-sourced servers** — verify in AC4

From 8-4 code review:
- **No tests for `--show-env`, `--read-only`/`--disabled` flags via real parse path** — AC8 covers these
- **No `quiet_summary` for MCP result shapes** — verify falls through to "ok" gracefully

### Critical Constraints

- **`async: false`** — ToolRegistry and ETS table are shared global state
- **`@moduletag :tmp_dir`** — use ExUnit-managed temp dirs, NOT `System.tmp_dir!()` (broke PathsResolve tests in Story 8-4)
- **Process.sleep(50) after send_line** — required for GenServer message processing; this is not a flaky sleep, it's the established pattern from `client_test.exs`
- **Do NOT spawn real subprocesses** — use FakePort exclusively
- **Do NOT modify production code** — this is a test-only story
- **Credo cyclomatic complexity limit is 9** — extract helpers if test setup gets complex
- **Zero-tolerance flaky test policy** — 50x stress test, no retries, no skips

### File Structure

```
familiar/
└── test/familiar/mcp/
    └── mcp_integration_test.exs  # NEW — integration test
```

### Previous Story Intelligence

From Story 8-4:
- `@moduletag :tmp_dir` is critical — `System.tmp_dir!()` leaves `.familiar/` in `/tmp` and breaks other tests
- OptionParser flags must be in `strict:` list with correct types (`:keep` for `--env`, `:boolean` for `--show-env`/`--read-only`/`--disabled`)
- `changeset_to_mcp_error/1` maps changeset errors to specific error atoms — test these through the full CLI path
- `deps()` base map needs `ensure_running_fn`, `health_fn`, `daemon_status_fn`, `stop_daemon_fn`
- `FakeRegistry` must be set via `Application.put_env(:familiar, :tool_registry, FakeRegistry)` for changeset validation

From Story 8-3:
- ETS table `:familiar_mcp_servers` is `:public` and `:set` — direct inspection via `:ets.lookup/2` is valid in tests
- `MCPClient.init/1` takes `config:`, `port_opener:`, `supervisor:` opts
- `MCPClient.reload_server/1` takes `port_opener:`, `supervisor:` opts as second arg
- `Client.status/1` returns `{status_atom, reason_string}`
- `Client.call_tool/3` sends `tools/call` JSON-RPC and awaits response

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 8-5] — Full scope with 10 test scenarios
- [Source: familiar/test/familiar/mcp/client_test.exs] — FakePort pattern, handshake helpers
- [Source: familiar/test/familiar/extensions/mcp_client_test.exs] — MCPClient extension test setup
- [Source: familiar/test/familiar/cli/mcp_command_test.exs] — CLI test DI pattern
- [Source: familiar/test/familiar/execution/harness_integration_test.exs] — Integration test structure
- [Source: familiar/lib/familiar/extensions/mcp_client.ex] — Extension under test
- [Source: familiar/lib/familiar/mcp/client.ex] — Client GenServer under test
- [Source: familiar/lib/familiar/mcp/client_supervisor.ex] — DynamicSupervisor
- [Source: familiar/lib/familiar/execution/tool_registry.ex] — Tool registration API
- [Source: familiar/lib/familiar/cli/main.ex] — CLI dispatch
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — Deferred items from 8-3 and 8-4 reviews

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- 9 integration tests covering AC1-AC8 in a single test file
- Uses FakePort pattern (from client_test.exs) with port_opener DI for client lifecycle
- Real ToolRegistry, real Ecto sandbox, real CLI dispatch (`Main.parse_args` → `Main.run`)
- Golden path test covers full lifecycle: CLI add → MCPClient.reload_server → handshake → ToolRegistry verification → CLI list → CLI remove → tool cleanup
- Disable/enable test verifies tools disappear/reappear through the full cycle
- Config+DB merge test verifies DB wins on collision with CaptureLog assertion
- Handshake failure test sends Protocol.encode_error to initialize, verifies `:handshake_failed` status, then recovers with reload
- Read-only filtering test asserts specific tools ARE and ARE NOT registered (3 read tools registered, 2 write tools filtered out)
- CLI flag tests use `Main.parse_args/1` to exercise real OptionParser path for `--disabled`, `--read-only`, `--show-env`
- Literal-secret warning captured via `CaptureIO.capture_io(:stderr, ...)`
- Client cleanup uses explicit `DynamicSupervisor.terminate_child` or manual tool unregistration when client is already dead (test supervisor differs from production ClientSupervisor)
- Credo nesting fix: extracted `poll_status/1` from `wait_for_status/3`
- 50x stress test: 50/50 clean, zero flakes

### File List

**New:**
- familiar/test/familiar/mcp/mcp_integration_test.exs (9 integration tests)
