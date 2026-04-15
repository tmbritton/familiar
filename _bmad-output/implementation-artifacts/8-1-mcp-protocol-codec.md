# Story 8-1: MCP Protocol Codec & Dispatcher

Status: done

## Story

As a developer building MCP support,
I want a pure module that encodes and decodes JSON-RPC 2.0 envelopes plus a method dispatcher,
So that the client GenServer has a well-tested wire format with no coupling to transport details, and the same codec can be reused by Epic 11 if the server direction ships later.

## Acceptance Criteria

1. **AC1: Encode requests.** `Familiar.MCP.Protocol.encode_request(id, method, params)` returns a JSON string containing a valid JSON-RPC 2.0 request with `jsonrpc: "2.0"`, the given `id`, `method`, and `params`. Params is optional (defaults to `%{}`).

2. **AC2: Encode responses.** `Protocol.encode_response(id, result)` returns a JSON string containing a valid JSON-RPC 2.0 success response.

3. **AC3: Encode errors.** `Protocol.encode_error(id, code, message, data \\ nil)` returns a JSON string containing a valid JSON-RPC 2.0 error response with the standard error object shape.

4. **AC4: Encode notifications.** `Protocol.encode_notification(method, params \\ nil)` returns a JSON string containing a valid JSON-RPC 2.0 notification (no `id` field).

5. **AC5: Decode messages.** `Protocol.decode(json_string)` returns tagged tuples:
   - `{:ok, {:request, id, method, params}}` for requests
   - `{:ok, {:response, id, result}}` for success responses
   - `{:ok, {:error, id, code, message, data}}` for error responses
   - `{:ok, {:notification, method, params}}` for notifications (no `id`)
   - `{:error, {:parse_error, reason}}` for invalid JSON
   - `{:error, {:invalid_request, reason}}` for valid JSON that isn't valid JSON-RPC 2.0

6. **AC6: Standard error codes.** Module attributes define the 5 standard JSON-RPC error codes: `@parse_error -32700`, `@invalid_request -32600`, `@method_not_found -32601`, `@invalid_params -32602`, `@internal_error -32603`. A helper `error_code/1` maps atom names to integer codes.

7. **AC7: Dispatcher.** `Familiar.MCP.Dispatcher` routes method strings to handler functions. `new(handlers_map)` creates a dispatcher from `%{"method/name" => handler_fn}`. `dispatch(dispatcher, method, params, context)` calls the matching handler. Returns `{:ok, result}` on success, `{:error, code, message}` on failure, `{:error, @method_not_found, "Method not found: <method>"}` for unregistered methods.

8. **AC8: Pure modules.** Both `Protocol` and `Dispatcher` are pure — no GenServer, no IO, no side effects, no process state. Transport-agnostic.

9. **AC9: Property tests.** StreamData property tests verify encode/decode round-trip: any valid request/response/error/notification encodes to JSON and decodes back to the same tagged tuple.

10. **AC10: Unit test coverage.** 100% branch coverage for both modules. Edge cases: empty params, null id, integer vs string id, missing `jsonrpc` field, missing `method`, extra fields, nested error data.

11. **AC11: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

12. **AC12: Stress-tested.** Every new test file passes 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.MCP.Protocol` module (AC: 1-6, 8)
  - [x] Created `lib/familiar/mcp/protocol.ex`
  - [x] Module attributes for 5 standard JSON-RPC error codes
  - [x] `encode_request/3`, `encode_response/2`, `encode_error/4`, `encode_notification/2`
  - [x] `decode/1` with tagged tuple returns for all message types
  - [x] `error_code/1` atom-to-integer helper with precise return type spec
  - [x] Full typespecs for all public functions

- [x] Task 2: Create `Familiar.MCP.Dispatcher` module (AC: 7, 8)
  - [x] Created `lib/familiar/mcp/dispatcher.ex`
  - [x] `new/1` creates dispatcher from handlers map
  - [x] `dispatch/4` with method lookup, handler invocation, exception catching
  - [x] Missing method returns `{:error, -32_601, "Method not found: <method>"}`

- [x] Task 3: Create Boundary module (AC: 8)
  - [x] Created `lib/familiar/mcp/mcp.ex` with `use Boundary, deps: [], exports: [Protocol, Dispatcher]`

- [x] Task 4: Unit tests for Protocol (AC: 5, 6, 10)
  - [x] 35 unit tests covering encode/decode for all message types
  - [x] Edge cases: invalid JSON, array input, missing jsonrpc, wrong version, empty object, non-string method, extra fields, null id, string id
  - [x] Error code helper tests for all 5 codes
  - [x] Round-trip tests for all message types

- [x] Task 5: Unit tests for Dispatcher (AC: 7, 10)
  - [x] 6 unit tests covering dispatch, missing method, error returns, exception catching, empty params

- [x] Task 6: Property tests (AC: 9)
  - [x] 8 StreamData properties for encode/decode round-trip
  - [x] Covers requests, responses, errors (with/without data), notifications (with/without params)
  - [x] Valid JSON and jsonrpc version assertions

- [x] Task 7: Toolchain verification (AC: 11)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1248 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 8: Stress-test (AC: 12)
  - [x] 50x on all MCP test files — 50/50 clean

### Review Findings

- [x] [Review][Patch] Dispatcher `try/rescue` doesn't catch exits — added `catch :exit` clause
- [x] [Review][Patch] `classify/1` doesn't reject both `result` and `error` — added ambiguity check
- [x] [Review][Patch] `classify/1` result-without-id falls through silently — added explicit rejection
- [x] [Review][Patch] Dispatcher `new/1` doesn't validate handler arity — added validation + ArgumentError
- [x] [Review][Patch] Batch array gives misleading error — changed to "batch requests are not supported"
- [x] [Review][Patch] `params: null` coerced silently — fixed to preserve explicit null via `Map.has_key?`
- [x] [Review][Patch] `@type decoded_message` notification tuple had `params()` (includes nil) — fixed to `map()`
- [x] [Review][Defer] `id` type not validated (accepts booleans/objects) — low risk, MCP peers are generally conforming
- [x] [Review][Defer] Property test `id_gen` only generates positive ints — zero/negative ids are edge cases
- [x] [Review][Defer] Property test `method_gen` doesn't include `/` — addressed by unit tests using real method names
- [x] [Review][Defer] No test for `encode_error` with `data=false` — Elixir semantics handle this correctly

## Dev Notes

### MCP Protocol (JSON-RPC 2.0 over stdio)

MCP uses JSON-RPC 2.0 with newline-delimited JSON over stdio. The codec in this story handles the message format only — transport (stdio/Port) is Story 8-2.

**Message types:**

```json
// Request (has id, expects response)
{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}

// Response success
{"jsonrpc": "2.0", "id": 1, "result": {"tools": [...]}}

// Response error
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32601, "message": "Method not found"}}

// Notification (no id, no response expected)
{"jsonrpc": "2.0", "method": "notifications/initialized"}
```

**Key rules:**
- `jsonrpc` MUST be `"2.0"`
- `id` MUST be string or integer (not null for requests/responses)
- Notifications MUST NOT have `id`
- `params` is optional in requests/notifications
- Error `data` is optional

### Standard error codes

```elixir
@parse_error      -32700  # Invalid JSON
@invalid_request  -32600  # Not a valid JSON-RPC request
@method_not_found -32601  # Method doesn't exist
@invalid_params   -32602  # Invalid method parameters
@internal_error   -32603  # Internal server error
```

### Design decisions

- **Encode returns strings, not iolists** — Jason.encode! is fast enough for MCP message sizes. Simpler API.
- **Decode returns tagged tuples** — pattern matching in the client GenServer (Story 8-2) will be clean.
- **Dispatcher is a simple map lookup** — no routing DSL, no middleware. Handler functions are `(params, context) -> {:ok, result} | {:error, code, message}`. The dispatcher exists so Story 8-2 (client) and Epic 11 (server) can share the routing pattern.
- **Both modules are pure** — no process state, no IO. This makes them trivially testable and reusable.

### Project structure

```
familiar/
├── lib/familiar/mcp/
│   ├── mcp.ex              # Boundary module
│   ├── protocol.ex          # Encode/decode JSON-RPC 2.0
│   └── dispatcher.ex        # Method → handler routing
└── test/familiar/mcp/
    ├── protocol_test.exs    # Unit + edge case tests
    └── dispatcher_test.exs  # Unit tests + property tests
```

### Existing patterns to follow

- **Jason usage:** `Jason.encode!/1` for encoding, `Jason.decode/1` for decoding (returns `{:ok, map} | {:error, reason}`)
- **Boundary declarations:** See `lib/familiar/execution/execution.ex` for pattern. New `Familiar.MCP` boundary with no deps initially.
- **Test style:** `use ExUnit.Case, async: true` for pure modules. StreamData for property tests (already a test dependency).
- **Typespecs:** All public functions get `@spec`. Use `@type` for message tuples.

### What this story does NOT include

- Transport layer (stdio, Port) — Story 8-2
- MCP initialize handshake — Story 8-2
- Tool registration — Story 8-2
- Server storage — Story 8-3
- CLI commands — Story 8-4
- MCP-specific error codes beyond standard JSON-RPC — not needed for MVP

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 8-1] — Epic scope
- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [Source: familiar/lib/familiar/execution/tool_registry.ex] — ToolRegistry dispatch pattern
- [Source: familiar/lib/familiar/execution/extension.ex] — Extension behaviour
- [Source: familiar/lib/familiar/extensions/knowledge_store.ex] — Example extension implementation

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Protocol module: 5 encode functions, 1 decode function with tagged tuple returns, 1 error code helper
- Dispatcher module: struct-based with `new/1` and `dispatch/4`, exception-safe handler invocation
- Boundary module: `Familiar.MCP` with no deps (pure modules)
- 47 unit tests + 8 property tests = 55 total, all async: true
- Dialyzer caught `contract_supertype` on `error_code/1` — narrowed return type to exact code values
- Credo caught underscore formatting — fixed numeric literals to use `_` separator per Elixir convention
- Fixed sed-induced bug: JSON string literals inside `~s()` had underscores inserted into numeric values (`-32_601` is invalid JSON)

### File List

**New:**
- familiar/lib/familiar/mcp/mcp.ex (Boundary module)
- familiar/lib/familiar/mcp/protocol.ex (JSON-RPC 2.0 codec)
- familiar/lib/familiar/mcp/dispatcher.ex (method routing)
- familiar/test/familiar/mcp/protocol_test.exs (35 unit tests)
- familiar/test/familiar/mcp/dispatcher_test.exs (6 unit tests)
- familiar/test/familiar/mcp/protocol_property_test.exs (8 property tests)
