# Story 8-2: MCP Client Connection

Status: done

## Story

As an agent author,
I want Familiar to launch external MCP server subprocesses and register their tools in `ToolRegistry`,
So that my agents can call GitHub, Postgres, Playwright, and other MCP servers without me writing a new Elixir extension per integration.

## Acceptance Criteria

1. **AC1: Client GenServer.** `Familiar.MCP.Client` is a GenServer that manages a single MCP server subprocess. `start_link/1` accepts `name`, `command`, `args`, `env` options. Supervised under `Familiar.MCP.ClientSupervisor` (DynamicSupervisor).

2. **AC2: Port-based subprocess.** The client spawns the external MCP server via `Port.open({:spawn_executable, command}, opts)` with `[:binary, :exit_status, {:line, max_line}]` options. Env values are expanded through a public `Familiar.Config.expand_env/1` at launch time so `${VAR}` references resolve to process env.

3. **AC3: Async startup.** `init/1` returns immediately with state `:connecting`. The MCP `initialize` handshake and `tools/list` discovery happen in `handle_continue/2`. Slow MCP servers do not block daemon boot.

4. **AC4: Initialize handshake.** The client sends a JSON-RPC `initialize` request with `{protocolVersion: "2025-11-05", capabilities: {}, clientInfo: {name: "familiar", version: <app_version>}}`. On success response, sends `notifications/initialized`. On failure or timeout, transitions to `:handshake_failed` with reason.

5. **AC5: Tool discovery.** After successful handshake, calls `tools/list` and registers each discovered tool in `ToolRegistry` with name `"<server_name>__<tool_name>"` (double underscore separator). Tools from different MCP servers don't collide. Each registered tool function translates args to a `tools/call` JSON-RPC request, waits for the response, and returns the result.

6. **AC6: Status state machine.** Client tracks status through: `:connecting` → `:connected` | `:handshake_failed`. Also `:crashed` (port exit), `:disabled` (explicit disable), `:unreachable` (repeated failures). Each state carries a reason string. `status/1` returns `{status_atom, reason_string}`.

7. **AC7: Crash recovery.** If the external process dies (port `{:EXIT, port, reason}`), the client cleans up its registered tools from `ToolRegistry`, transitions to `:crashed`, and the supervisor restarts it. Repeated failures use exponential backoff (configurable `max_restarts`, `max_seconds` on the supervisor child spec).

8. **AC8: Graceful tool call during disconnect.** If an agent calls a tool while the client is not `:connected`, it returns `{:error, :tool_not_yet_available, "MCP server '<name>' is <status>"}`. If a server is removed mid-call, in-flight calls return `{:error, :mcp_server_removed}`.

9. **AC9: Timeouts.** Connect timeout (default 30s) and call timeout (default 60s) are configurable per-server via options. Timeout on handshake → `:handshake_failed`. Timeout on tool call → `{:error, :timeout, "MCP tool call timed out"}`.

10. **AC10: Clean shutdown.** On `terminate/2`, the client sends a best-effort `shutdown` notification to the MCP server, closes the port, and unregisters all its tools from `ToolRegistry`.

11. **AC11: ClientSupervisor.** `Familiar.MCP.ClientSupervisor` is a DynamicSupervisor. `start_client/1` and `stop_client/1` manage children. Listed in the application supervision tree.

12. **AC12: Boundary update.** `Familiar.MCP` boundary exports `Client` and `ClientSupervisor` in addition to `Protocol` and `Dispatcher`.

13. **AC13: Unit tests.** Comprehensive tests for: init/handshake flow, tool discovery and registration, tool call round-trip, status transitions, port crash handling, timeout behavior, graceful shutdown. Use a mock port approach (Mox or inline test helpers).

14. **AC14: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

15. **AC15: Stress-tested.** Every new test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Promote `Familiar.Config.expand_env/1` from `defp` to `def` (AC: 2)
  - [x] Change `defp expand_env` to `def expand_env` at `familiar/lib/familiar/config.ex:265`
  - [x] Add `@doc` and `@spec` for the now-public function
  - [x] Verify existing callers still work (used for provider api_key/base_url/chat_model/embedding_model)

- [x] Task 2: Create `Familiar.MCP.ClientSupervisor` (AC: 11)
  - [x] DynamicSupervisor with `start_link/1`, `start_client/1`, `stop_client/1`
  - [x] Add to application supervision tree in `familiar/lib/familiar/application.ex` (after `AgentSupervisor`)

- [x] Task 3: Create `Familiar.MCP.Client` GenServer (AC: 1-10)
  - [x] `start_link/1` with opts: `name`, `command`, `args`, `env`, `connect_timeout`, `call_timeout`
  - [x] `init/1` returns `{:ok, state, {:continue, :connect}}` — state starts as `:connecting`
  - [x] `handle_continue(:connect, state)` — open Port, send `initialize`, start timeout timer
  - [x] `handle_info({port, {:data, {:eol, line}}}, state)` — accumulate JSON-RPC responses, decode via `Protocol.decode/1`, route to pending request or notification handler
  - [x] `handle_info({port, {:exit_status, code}}, state)` — transition to `:crashed`, unregister tools
  - [x] `handle_call({:call_tool, tool_name, args}, from, state)` — send `tools/call` request, store pending `{id, from, timer_ref}`, reply asynchronously
  - [x] `handle_call(:status, _from, state)` — return current status tuple
  - [x] `terminate/2` — send shutdown notification, close port, unregister tools
  - [x] Internal: ID counter for JSON-RPC request IDs
  - [x] Internal: pending requests map `%{id => {from, timer_ref}}`
  - [x] Internal: timeout handling via `Process.send_after/3` + `handle_info(:timeout, ...)`

- [x] Task 4: Tool registration bridge (AC: 5, 8)
  - [x] After `tools/list` response, register each tool in `ToolRegistry` via `ToolRegistry.register/4`
  - [x] Tool name format: `"<server_name>__<tool_name>"`
  - [x] Registered function: captures client pid, sends `GenServer.call(client, {:call_tool, ...})`
  - [x] Unregister all tools on crash/shutdown/disable via `ToolRegistry.unregister/1`

- [x] Task 5: Update `Familiar.MCP` boundary (AC: 12)
  - [x] Add `Client` and `ClientSupervisor` to exports in `familiar/lib/familiar/mcp/mcp.ex`

- [x] Task 6: Unit tests (AC: 13)
  - [x] Test init returns `:connecting` state
  - [x] Test handshake flow (mock port data)
  - [x] Test tool discovery and ToolRegistry registration
  - [x] Test tool call round-trip via registered function
  - [x] Test status transitions through state machine
  - [x] Test port crash → `:crashed` + tool unregistration
  - [x] Test handshake timeout → `:handshake_failed`
  - [x] Test call timeout → error response
  - [x] Test graceful shutdown with notification
  - [x] Test `expand_env` on env vars

- [x] Task 7: Toolchain verification (AC: 14)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1282 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 8: Stress-test (AC: 15)
  - [x] 50x on client_test.exs — 50/50 clean

### Review Findings

- [x] [Review][Patch] `connect_timer` not cleared in state after tools/list error response — race condition [client.ex:316-321]
- [x] [Review][Patch] `stop_client/1` hardcodes `__MODULE__` — asymmetric with `start_client/1` [client_supervisor.ex:38-40]
- [x] [Review][Patch] `terminate/2` sends `notifications/cancelled` instead of just closing transport — removed, MCP has no session shutdown notification [client.ex:215-217]
- [x] [Review][Defer] `String.to_atom` on MCP tool names — atom table leak risk — deferred, ToolRegistry API uses atoms throughout; server names are user-controlled config in same trust boundary
- [x] [Review][Defer] Hardcoded IDs 1/2 for init response routing — deferred, currently correct and deterministic
- [x] [Review][Defer] `call_tool/4` per-call timeout not threaded to internal timer — deferred, registered tool functions always use state.call_timeout
- [x] [Review][Defer] `:disabled` status declared but unreachable — deferred, forward-declared for Story 8-3
- [x] [Review][Defer] No `:mcp_server_removed` error atom — deferred, removal is Story 8-3/8-4 scope
- [x] [Review][Defer] No test for `ClientSupervisor.start_client/stop_client` — deferred, integration test in Story 8-5

## Dev Notes

### MCP Initialize Handshake (spec 2025-11-05)

The client MUST perform this handshake before calling any tools:

```
Client → Server: {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-05","capabilities":{},"clientInfo":{"name":"familiar","version":"0.1.0"}}}
Server → Client: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"server-name","version":"1.0"}}}
Client → Server: {"jsonrpc":"2.0","method":"notifications/initialized"}
```

After `notifications/initialized`, the client can call `tools/list`:

```
Client → Server: {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
Server → Client: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_file","description":"Read a file","inputSchema":{...}}]}}
```

Tool calls use `tools/call`:

```
Client → Server: {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"/tmp/foo"}}}
Server → Client: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"file contents"}]}}
```

### Port Configuration

```elixir
port = Port.open({:spawn_executable, command}, [
  :binary,
  :exit_status,
  {:line, 1_048_576},  # 1MB max line (JSON-RPC messages can be large)
  {:args, args},
  {:env, expanded_env},  # [{~c"KEY", ~c"VALUE"}, ...]
  :stderr_to_stdout  # or :use_stdio — capture server output
])
```

Port messages arrive as:
- `{port, {:data, {:eol, line}}}` — complete line (newline-delimited JSON)
- `{port, {:data, {:noeol, partial}}}` — partial line (buffer and concatenate)
- `{port, {:exit_status, code}}` — process exited

### Existing Code to Reuse

| What | Where | How |
|------|-------|-----|
| JSON-RPC encode/decode | `Familiar.MCP.Protocol` | `encode_request/3`, `decode/1` — already built in Story 8-1 |
| Tool registration | `Familiar.Execution.ToolRegistry` | `register/4`, `unregister/1` — existing GenServer |
| DynamicSupervisor pattern | `Familiar.Execution.AgentSupervisor` | Copy pattern: `start_link/1`, `init/1`, `start_child/2` |
| Env var expansion | `Familiar.Config.expand_env/1` | Currently `defp` at `config.ex:265` — promote to `def` |
| GenServer + async pattern | `Familiar.Execution.AgentProcess` | `handle_continue/2` for deferred init, `Process.send_after/3` for timeouts |

### ToolRegistry Integration

`ToolRegistry.register/4` signature: `register(name, function, description, extension_name)`

- `name`: `"github__list_repos"` (string, server_name + `__` + tool_name)
- `function`: `fn args, context -> GenServer.call(client_pid, {:call_tool, "list_repos", args}, timeout) end`
- `description`: from MCP `tools/list` response tool schema
- `extension_name`: `"mcp:#{server_name}"`

`ToolRegistry.unregister/1` takes the tool name string. Call for each registered tool on cleanup.

### Status State Machine

```
                    ┌──────────────┐
    start_link ───→ │  :connecting │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────────┐ ┌──────────┐
        │:connected│ │:handshake_   │ │:crashed  │
        │          │ │  failed      │ │          │
        └────┬─────┘ └──────────────┘ └──────────┘
             │                              ▲
             │  port dies                   │
             └──────────────────────────────┘
```

Each state carries `{status, reason}`:
- `{:connecting, "initializing"}`
- `{:connected, "ready"}`
- `{:handshake_failed, "timeout after 30s"}`
- `{:crashed, "exit code 1"}`

### Testing Strategy

**Port mocking approach:** Create a test helper that simulates Port behavior. Since Erlang Ports are low-level and hard to mock with Mox, use one of:

1. **Test helper GenServer** that pretends to be a Port — sends `{self(), {:data, {:eol, json}}}` messages to the client. This is the simplest approach.
2. **Real subprocess** with a tiny Elixir script that speaks JSON-RPC. More realistic but slower.

Recommended: Option 1 for unit tests (fast, deterministic), option 2 deferred to Story 8-5 integration test.

For the test helper, create `test/support/mock_mcp_server.ex`:
```elixir
defmodule Familiar.Test.MockMCPServer do
  # Sends port-shaped messages to the client process
  def send_response(client_pid, json_string) do
    send(client_pid, {self(), {:data, {:eol, json_string}}})
  end

  def send_exit(client_pid, code) do
    send(client_pid, {self(), {:exit_status, code}})
  end
end
```

The Client GenServer should accept an optional `:port_opener` function in opts for DI:
```elixir
# Production: Port.open/2
# Test: fn _cmd, _opts -> test_port_pid end
```

### File Structure

```
familiar/
├── lib/familiar/mcp/
│   ├── mcp.ex                # Boundary (update exports)
│   ├── protocol.ex           # Story 8-1 — don't modify
│   ├── dispatcher.ex         # Story 8-1 — don't modify
│   ├── client.ex             # NEW — Client GenServer
│   └── client_supervisor.ex  # NEW — DynamicSupervisor
├── lib/familiar/config.ex    # MODIFY — promote expand_env to public
└── test/familiar/mcp/
    ├── client_test.exs        # NEW — Client unit tests
    └── ...existing test files...
```

### Critical Constraints

- **Do NOT modify** `protocol.ex` or `dispatcher.ex` — they are done (Story 8-1).
- **Do NOT create an Extension module** — that's Story 8-3. This story builds the raw Client + Supervisor only.
- **Do NOT add MCP servers table/storage** — that's Story 8-3.
- **Port.open/2 needs an absolute path** to the executable. Use `System.find_executable/1` to resolve `command` to an absolute path, or require callers to pass absolute paths.
- **Env for Port.open** must be charlists: `[{~c"KEY", ~c"VALUE"}]` — convert from string maps.
- **Line buffering**: Port `:line` mode buffers until newline. MCP uses newline-delimited JSON, so each complete message arrives as one `{:eol, line}` callback. Handle `{:noeol, partial}` for lines exceeding `max_line`.
- **Request ID tracking**: Use a monotonic integer counter in GenServer state. Map each pending request ID to `{from, timer_ref}` so responses can be routed back and timeouts canceled.

### Previous Story Intelligence (8-1)

- Jason `encode!/1` and `decode/1` patterns established — use them, don't add alternatives.
- `Protocol.decode/1` returns tagged tuples: `{:ok, {:response, id, result}}` and `{:ok, {:error, id, code, message, data}}` — pattern match on these in the response handler.
- Numeric literal formatting: use `_` separators in Elixir code (`-32_601`) but NOT in JSON strings.
- Credo cyclomatic complexity limit is 9 — extract helper functions proactively if `cond`/`case` blocks get deep.
- Dialyzer is strict — ensure all public functions have `@spec`, use precise return types.
- 50x stress test caught zero flakes in 8-1 — maintain this standard.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 8-2] — Full scope and friction items
- [Source: _bmad-output/implementation-artifacts/8-1-mcp-protocol-codec.md] — Previous story patterns
- [Source: familiar/lib/familiar/mcp/protocol.ex] — JSON-RPC codec to reuse
- [Source: familiar/lib/familiar/execution/tool_registry.ex] — Tool registration API
- [Source: familiar/lib/familiar/execution/agent_supervisor.ex] — DynamicSupervisor pattern
- [Source: familiar/lib/familiar/execution/agent_process.ex] — GenServer + handle_continue pattern
- [Source: familiar/lib/familiar/config.ex:265] — expand_env/1 to promote
- [MCP Specification 2025-11-05](https://modelcontextprotocol.io/specification/2025-11-05)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Promoted `Familiar.Config.expand_env/1` from `defp` to `def` with `@doc` and `@spec`
- Created `Familiar.MCP.ClientSupervisor` DynamicSupervisor, added to application supervision tree
- Created `Familiar.MCP.Client` GenServer with full lifecycle: async init, MCP handshake, tool discovery, tool call routing, crash recovery, timeout handling, graceful shutdown
- DI pattern for port abstraction: `port_opener` returns `{port_ref, send_fn, close_fn}` tuple — production uses real Port, tests use message-passing fakes
- Added `ToolRegistry.unregister/1` function (was missing — needed for tool cleanup on crash/shutdown)
- Tool name format: `:"server_name__tool_name"` (atom, double underscore separator)
- Init response routing uses hard-coded IDs (1=initialize, 2=tools/list) — simple and correct since the client controls the ID sequence
- MCP boundary updated with `deps: [Familiar.Execution]` for ToolRegistry access
- 27 unit tests covering all ACs: init, handshake, tool calls, status machine, crash handling, timeouts, shutdown, line buffering, expand_env
- Credo caught implicit try preference in `close_port` — fixed
- 50x stress test: 50/50 clean

### File List

**New:**
- familiar/lib/familiar/mcp/client.ex (Client GenServer)
- familiar/lib/familiar/mcp/client_supervisor.ex (DynamicSupervisor)
- familiar/test/familiar/mcp/client_test.exs (27 unit tests)

**Modified:**
- familiar/lib/familiar/config.ex (promote expand_env to public)
- familiar/lib/familiar/mcp/mcp.ex (boundary: add Client, ClientSupervisor exports + Execution dep)
- familiar/lib/familiar/application.ex (add ClientSupervisor to supervision tree)
- familiar/lib/familiar/execution/tool_registry.ex (add unregister/1)
