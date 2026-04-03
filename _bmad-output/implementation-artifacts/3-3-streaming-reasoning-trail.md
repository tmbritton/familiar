# Story 3.3: Streaming Reasoning Trail

Status: done

## Story

As a user,
I want to see what the familiar is doing during planning in real time,
So that I can build trust in the spec being generated and understand how it verified assumptions.

## Acceptance Criteria

### AC1: Tool Call Streaming
**Given** `fam plan` is generating a spec
**When** the planning engine makes tool calls (file reads, context queries, verification checks)
**Then** each conclusion is streamed to the terminal as a single line (FR24b)
**And** output is ~10-20 lines per spec, one per conclusion
**And** each line corresponds to actual tool use, not post-hoc narrative

### AC2: Heartbeat Indicator
**Given** the planning engine is working but hasn't produced output in 5+ seconds
**When** the heartbeat interval elapses
**Then** a heartbeat indicator is shown so the user knows the system is still working

### AC3: Column Width Compliance
**Given** the streaming trail is displayed
**When** the terminal is 80 columns wide
**Then** all trail output is legible without wrapping (UX-DR25)

### AC4: Progressive Hints
**Given** this is the user's first `fam plan` (first ~3 sessions)
**When** the trail streams
**Then** progressive hints explain what each line means (UX-DR24)
**And** hints fade after approximately 3 planning sessions

### AC5: Test Coverage
**Given** the trail is implemented
**When** unit tests run
**Then** PubSub event publishing from planning engine is tested
**And** trail formatter is tested as a pure function (event → formatted string) separately from PubSub integration
**And** column width compliance at 80 columns is verified on formatter output
**And** near-100% coverage on trail module

## Tasks / Subtasks

- [x] Task 1: Trail event types and PubSub broadcasting (AC: #1, #5)
  - [x] Define `Planning.Trail` module with event struct: `%Trail.Event{type, path, result, timestamp}`
  - [x] Event types: `:file_read`, `:knowledge_search`, `:verification_result`, `:spec_started`, `:spec_complete`
  - [x] `Trail.broadcast/2` — wraps `Phoenix.PubSub.broadcast(Familiar.PubSub, topic, event)`
  - [x] Topic: `"planning:trail:#{session_id}"`
  - [x] Tests: broadcast/subscribe roundtrip, event struct validation (6 tests)

- [x] Task 2: Inject trail events into SpecGenerator tool dispatch (AC: #1)
  - [x] Modify `SpecGenerator.dispatch_single_tool/3` to broadcast a trail event after each tool dispatch
  - [x] Broadcast `:spec_started` at start of `generate_with_tools/3`
  - [x] Broadcast `:spec_complete` at end of `finalize_spec/4`
  - [x] Pass `session_id` through opts for topic construction
  - [x] DI: `trail_mod` opt (default `Planning.Trail`) for test stubbing
  - [x] Tests: verify events broadcast during tool dispatch, stub trail module (6 tests)

- [x] Task 3: Trail formatter — pure function (AC: #1, #3, #5)
  - [x] Create `Planning.TrailFormatter` module
  - [x] `format/1` — converts `Trail.Event` → single-line string, max 80 chars
  - [x] Format examples:
    - `:file_read` → `"  Reading db/migrations/001_init.sql"`
    - `:knowledge_search` → `"  Searching knowledge: auth patterns"`
    - `:verification_result` → `"  ✓ Verified: users table schema"` or `"  ⚠ Unverified: rate limiting"`
    - `:spec_started` → `"Generating spec..."`
    - `:spec_complete` → `"Spec complete: 5 verified, 2 unverified"`
  - [x] Truncation: paths/queries truncated with `…` to fit 80 columns (2-char indent + content)
  - [x] Tests: format each event type, truncation at 80 chars, property test for width compliance (12 tests + 1 property)

- [x] Task 4: Heartbeat indicator (AC: #2)
  - [x] `Planning.TrailFormatter.heartbeat/0` → returns heartbeat string (e.g., `"  ..."` or `"  Still working..."`)
  - [x] CLI consumer tracks time since last event; emits heartbeat at 5s interval
  - [x] Heartbeat logic in `Planning.Trail.subscribe_with_heartbeat/2` — wraps PubSub subscription with Process.send_after-based timer that resets on each event
  - [x] Tests: heartbeat emitted after timeout, heartbeat suppressed when events flowing (4 tests)

- [x] Task 5: Progressive hints (AC: #4)
  - [x] `Planning.TrailFormatter.format/2` accepts `hint: true | false` option
  - [x] When `hint: true`, appends brief explanation in parentheses:
    - `:file_read` → `"  Reading db/migrations/001_init.sql (checking file contents)"`
    - `:knowledge_search` → `"  Searching knowledge: auth patterns (querying project context)"`
    - `:verification_result` → `"  ✓ Verified: users table schema (confirmed by file read)"`
  - [x] Session count check: `Planning.Trail.show_hints?/0` — counts completed sessions in DB, returns `true` if < 3
  - [x] Hint text must still fit within 80 columns (truncate path more aggressively if needed)
  - [x] Tests: format with/without hints, hint threshold logic, width compliance with hints (6 tests)

- [x] Task 6: CLI integration — subscribe and print trail (AC: #1, #2, #3)
  - [x] In `fam plan` flow (CLI/Main), after calling `Engine.generate_spec/2`:
    - Subscribe to trail topic before triggering spec generation
    - Print each received event via `TrailFormatter.format/1`
    - Show heartbeat when idle > 5s
  - [x] Since `generate_spec` is synchronous, run spec generation in a Task and subscribe in the calling process
  - [x] Use `Task.Supervisor.async_nolink(Familiar.TaskSupervisor, fn -> ... end)` for spec generation
  - [x] Tests: CLI integration with stub trail events (4 tests)

- [x] Task 7: Channel integration — push trail events to WebSocket (AC: #1)
  - [x] Extend `PlanningChannel` to subscribe to trail topic on `"generate_spec"` message
  - [x] `handle_info` for trail events → `push(socket, "trail:event", payload)`
  - [x] Payload: `%{type: event.type, text: TrailFormatter.format(event)}`
  - [x] Tests: channel receives and pushes trail events (3 tests)

### Review Findings

- [x] [Review][Decision] D1: PlanningChannel generate_spec — resolved: async Task with spec:complete/spec:error push events
- [x] [Review][Decision] D2: Error tuple convention — resolved: all Trail public functions return tagged tuples
- [x] [Review][Patch] P1: Heartbeat timer leak — fixed: return {result, final_ref} from receive loop [main.ex]
- [x] [Review][Patch] P2: trail_broadcast_verification crash — fixed: catch-all clause + string interpolation for status [spec_generator.ex]
- [x] [Review][Patch] P3: receive_trail_events no timeout — fixed: after 300_000 clause [main.ex]
- [x] [Review][Patch] P4: truncate_to_width inconsistency — fixed: consistent String.length, @max_width - 1 for all lines [trail_formatter.ex]
- [x] [Review][Patch] P5: Channel session_id type — fixed: normalize_session_id/1 for string or integer [planning_channel.ex]
- [x] [Review][Patch] P6: show_hints? DB coupling — kept in Trail with rescue; minimal dependency, extraction would over-engineer
- [x] [Review][Defer] W1: `text_formatter("generate-spec")` dispatch — formatter defined but dispatch mechanism unclear from diff alone; existing pattern handles it via `text_formatter(elem(parsed, 0))` — deferred, pre-existing pattern

## Dev Notes

### Architecture Constraints

- **Hexagonal architecture**: All LLM calls through `Providers.chat/2` or `stream_chat/2`, file reads through `Familiar.System.FileSystem` behaviour, knowledge queries through `Knowledge.search/1`.
- **PubSub is the event bus**: `Phoenix.PubSub` (as `Familiar.PubSub`) is already in the supervision tree (`application.ex:19`). Use `Phoenix.PubSub.broadcast/3` for trail events — do NOT create a custom event system.
- **One verification log, two consumers**: The tool call log feeds both the spec's inline verification marks (Story 3.2, done) and the streaming reasoning trail (this story). Story 3.2 builds the log in `SpecGenerator.dispatch_single_tool/3` — this story adds broadcast calls at the same points.
- **Trail events are fire-and-forget**: Broadcasting must not block or fail the spec generation pipeline. Use `broadcast/3` (not `broadcast!/3`) and ignore errors.
- **Error tuples**: All public functions return `{:ok, result}` or `{:error, {atom, map}}`.
- **SecretFilter**: Not needed on trail events — they contain only file paths and search queries, not file contents.

### Existing Code to Reuse

| Module | API | Use For |
|--------|-----|---------|
| `Planning.SpecGenerator` | `generate/2`, `dispatch_single_tool/3` | Inject trail broadcasts at tool dispatch points |
| `Planning.Verification` | `verify_claims/2` result structs | Derive verification trail events from verification results |
| `Familiar.PubSub` | `Phoenix.PubSub.broadcast/3` | Event distribution |
| `FamiliarWeb.PlanningChannel` | `handle_in`, `handle_info` | Extend for trail event push |
| `Familiar.Providers.StreamEvent` | `t()` type | Reference for stream event types (not directly consumed — trail events are higher-level) |
| `Planning.Session` | Ecto schema | Count completed sessions for hint threshold |

### Key Design Decisions

**Trail events vs. StreamEvent**: Trail events are NOT the same as `Providers.StreamEvent`. StreamEvents are low-level LLM token deltas. Trail events are high-level semantic events ("reading file X", "verified assumption Y"). Trail events are derived from tool dispatch actions in `SpecGenerator`, not from LLM stream chunks.

**Synchronous generate_spec + async trail**: `Engine.generate_spec/2` is currently synchronous. For the CLI to both display trail events AND wait for completion, spec generation must run in a separate process (via `Task.Supervisor`). The CLI process subscribes to PubSub and prints events while awaiting the Task result.

**Heartbeat via Process.send_after**: The heartbeat is a client-side concern. The `Trail.subscribe_with_heartbeat/2` helper starts a recurring timer that sends `:heartbeat` to the subscribing process. Each real trail event resets the timer. This avoids server-side heartbeat complexity.

**Progressive hints via session count**: Query `Repo.aggregate(Session, :count, :id)` where status = "completed". If < 3, show hints. This is a simple heuristic — no need for per-user tracking since Familiar is single-user.

### Previous Story Intelligence

**From Story 3.1 review findings:**
- PubSub explicitly earmarked for Story 3.3: "Use for streaming events in Story 3.3"
- `Providers.stream_chat/2` exists but is NOT needed here — trail events come from tool dispatch, not LLM token streaming
- Channel DI uses `Application.get_env(:familiar, :planning_engine_opts, [])` — extend this pattern for trail opts

**From Story 3.2 review findings:**
- Tool dispatch loop is in `SpecGenerator.do_tool_loop/5` (line 116) — this is where trail events should be injected
- `dispatch_single_tool/3` returns `{result, log_entry}` — broadcast trail event using `log_entry` data
- `finalize_spec/4` runs verification — broadcast verification results as trail events
- W1 (deferred): StubFileSystem duplicated across test files — continue using per-file stubs for now

**From Story 3.2 completion notes:**
- 659 tests + 12 properties, 0 failures. Credo strict: 0 issues. Do not regress.
- Tool call log structure: `%{type: "file_read" | "context_query", path: string, timestamp: DateTime}`

### Testing Standards

- **Mox for all behaviours**: LLM, FileSystem, Shell, Notifications, Clock, Embedder
- **Ecto sandbox**: `use Familiar.DataCase, async: true` where possible (async: false if shared Application.put_env)
- **Pure function tests**: TrailFormatter tested without PubSub — input event → output string
- **Property test**: TrailFormatter output never exceeds 80 characters for any event type with any path/query length
- **PubSub tests**: Use `Phoenix.PubSub.subscribe/2` in test process, trigger broadcast, assert_receive
- **Trail DI**: `trail_mod` opt in SpecGenerator to stub trail broadcasting in existing spec_generator tests

### Project Structure Notes

New files to create:
```
familiar/lib/familiar/planning/
├── trail.ex               # PubSub broadcasting, event struct, subscribe_with_heartbeat
└── trail_formatter.ex     # Pure function: event → formatted string

familiar/test/familiar/planning/
├── trail_test.exs         # PubSub broadcast/subscribe tests, heartbeat tests
└── trail_formatter_test.exs  # Format tests, width compliance, property test
```

Modified files:
```
familiar/lib/familiar/planning/spec_generator.ex  # Add trail broadcasts at dispatch points
familiar/lib/familiar/cli/main.ex                  # Subscribe + print trail during spec gen
familiar/lib/familiar_web/channels/planning_channel.ex  # Push trail events to WebSocket
familiar/test/familiar/planning/spec_generator_test.exs  # Add trail_mod stub
familiar/test/familiar/cli/main_test.exs           # Trail display tests
familiar/test/familiar_web/channels/planning_channel_test.exs  # Trail push tests
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 3, Story 3.3]
- [Source: _bmad-output/planning-artifacts/architecture.md — Testing strategy, PubSub, StreamEvent]
- [Source: _bmad-output/planning-artifacts/prd.md — FR24b streaming reasoning trail]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR24, UX-DR25, watch view]
- [Source: _bmad-output/implementation-artifacts/3-1-planning-conversation-engine.md — PubSub earmark, Engine architecture]
- [Source: _bmad-output/implementation-artifacts/3-2-spec-generation-verification.md — Tool dispatch loop, verification log]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Task 1: Trail module with Event struct, PubSub broadcast/subscribe, subscribe_with_heartbeat with Process.send_after, show_hints? counting completed sessions. 9 tests.
- Task 2: Injected trail broadcasts into SpecGenerator — spec_started at generate entry, tool events after each dispatch_single_tool, verification_result events during verify_with_freshness, spec_complete at finalize. DI via trail_mod opt with map/module dispatch (same pattern as providers). 3 new tests + StubTrail added to all 13 existing tests.
- Task 3: TrailFormatter pure function — format/1 converts Event to single-line string with 2-char indent. Truncation with … for paths exceeding 80 columns. Handles all 5 event types + unknown. 19 tests + 1 property test (width compliance for any path).
- Task 4: Heartbeat implemented in Trail.subscribe_with_heartbeat (Task 1) and TrailFormatter.heartbeat/0 (Task 3). Tests in both files.
- Task 5: Progressive hints via format/2 with hint: true option. Appends explanatory parentheticals. show_hints?/0 counts completed sessions (< 3 = show hints). Width compliance maintained with hints. Tests in both trail_test and trail_formatter_test.
- Task 6: CLI `fam generate-spec <id>` command. Subscribes to trail topic, runs spec generation in Task.Supervisor.async_nolink, prints trail events to stderr via receive loop with heartbeat reset. 4 new tests.
- Task 7: PlanningChannel extended with generate_spec handler (subscribes to trail topic) and handle_info for trail events (pushes "trail:event" with type + formatted text). 3 new tests.
- Total: 38 new tests + 1 new property. Full suite: 702 tests + 14 properties, 0 failures. Credo strict: 0 issues.

### Change Log

- 2026-04-02: Story 3.3 implemented — Streaming reasoning trail with PubSub events, formatter, heartbeat, progressive hints, CLI and Channel integration

### File List

- familiar/lib/familiar/planning/trail.ex (new)
- familiar/lib/familiar/planning/trail_formatter.ex (new)
- familiar/lib/familiar/planning/spec_generator.ex (modified — trail broadcasts at tool dispatch points)
- familiar/lib/familiar/cli/main.ex (modified — generate-spec command with trail display)
- familiar/lib/familiar_web/channels/planning_channel.ex (modified — generate_spec handler, trail event push)
- familiar/test/familiar/planning/trail_test.exs (new)
- familiar/test/familiar/planning/trail_formatter_test.exs (new)
- familiar/test/familiar/planning/spec_generator_test.exs (modified — StubTrail, trail broadcast tests)
- familiar/test/familiar/cli/main_test.exs (modified — generate-spec command tests)
- familiar/test/familiar_web/channels/planning_channel_test.exs (modified — trail event push tests)
