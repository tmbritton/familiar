# Story 3.1: Planning Conversation Engine

Status: done

## Story

As a user,
I want to describe a feature in natural language and have a context-aware conversation that sharpens my intent,
So that the system understands what I want to build without me manually providing context.

## Acceptance Criteria

### AC1: Context-Aware Conversation Start
**Given** the user runs `fam plan "add user accounts"`
**When** the planning conversation starts
**Then** the system queries the knowledge store for relevant context before asking any question
**And** the system never asks a question it can answer from existing context
**And** the conversation adapts depth to intent clarity — short/vague prompts trigger more questions (3-5), detailed prompts with specific file references trigger fewer (0-2). This is prompt-instructed behaviour, not a separate classifier.

### AC2: Novel Clarifying Questions
**Given** a planning conversation is in progress
**When** the system asks clarifying questions
**Then** questions surface edge cases, ambiguities, or unresolved decisions
**And** repeat questions are treated as a system failure
**And** context-influenced questions cite their source ("Based on your repository pattern in db/...")

### AC3: Conversation Resume
**Given** a planning conversation is in progress
**When** the user leaves and returns later
**Then** `fam plan --resume` resumes the conversation from where it left off
**And** message history is loaded from the `planning_messages` SQLite table (session_id, role, content, tool_calls, timestamp)
**And** the system does not re-ask previously answered questions

### AC4: WebSocket Transport
**Given** the planning engine communicates interactively
**When** `fam plan` is invoked
**Then** the conversation runs over Phoenix Channel (WebSocket) for bidirectional streaming
**And** clarifying questions and user responses flow over a single connection

### AC5: Librarian Agent Integration
**Given** the planning engine needs knowledge context
**When** it queries the knowledge store
**Then** queries go through an ephemeral Librarian GenServer (under DynamicSupervisor)
**And** the Librarian performs multi-hop retrieval: evaluate results -> detect gaps -> re-query with refined terms -> synthesize
**And** the Librarian spins up per query and shuts down after delivering results (no long-running process)
**And** `fam search` defaults to librarian-curated results; `--raw` flag bypasses to direct `Knowledge.search/1`

### AC6: Test Coverage
**Given** the planning conversation engine is implemented
**When** unit tests run
**Then** context query integration, adaptive depth logic, and conversation persistence are tested
**And** prompt assembly for planning is tested as a pure function
**And** near-100% coverage on planning engine module
**And** 100% coverage on `Planning.PromptAssembly` (critical module)

## Tasks / Subtasks

- [x] Task 1: Database migration for planning_messages (AC: #3)
  - [x] Create migration `create_planning_messages` with columns: id, session_id (string, indexed), role (string), content (text), tool_calls (text, JSON-encoded), inserted_at (utc_datetime)
  - [x] Create migration `create_planning_sessions` with columns: id, description (text), status (string: "active", "completed", "abandoned"), inserted_at, updated_at
  - [x] Create `Planning.Message` Ecto schema
  - [x] Create `Planning.Session` Ecto schema
  - [x] Tests: schema changeset validation

- [x] Task 2: Librarian Agent — ephemeral GenServer (AC: #5)
  - [x] Create `Planning.Librarian` GenServer module under DynamicSupervisor
  - [x] `start_link/1` accepts query string + opts, performs retrieval, returns results, then stops
  - [x] Multi-hop retrieval: call `Knowledge.search/1` -> evaluate relevance -> if gaps detected, refine query terms and re-query (max 3 hops)
  - [x] Summarize results via LLM (Providers.chat) into a concise context block with source citations
  - [x] Add `{DynamicSupervisor, name: Familiar.LibrarianSupervisor, strategy: :one_for_one}` to Application supervision tree
  - [x] Public API: `Librarian.query(text, opts)` — starts ephemeral GenServer, awaits result, GenServer terminates
  - [x] Wire `fam search` to use Librarian by default; add `--raw` flag for direct Knowledge.search
  - [x] Tests: Mox LLM for summarization, verify GenServer lifecycle (starts, returns, terminates), multi-hop logic, raw bypass

- [x] Task 3: Prompt Assembly — pure function module (AC: #1, #2)
  - [x] Create `Planning.PromptAssembly` module
  - [x] `assemble/2` takes `{description, context_block, conversation_history}` -> returns `{system_prompt, messages}`
  - [x] System prompt instructs LLM on: adaptive depth (vague = 3-5 questions, detailed = 0-2), cite sources, never repeat questions already answered in history, surface edge cases/ambiguities
  - [x] Context block inserted as system message with knowledge citations
  - [x] Conversation history appended as alternating user/assistant messages
  - [x] 100% test coverage: pure function, no side effects, property tests for output structure

- [x] Task 4: Planning Engine core (AC: #1, #2, #3)
  - [x] Create `Planning.Engine` module
  - [x] `start_plan/2` — creates Session, queries Librarian for context, assembles prompt, calls `Providers.chat`, persists messages, returns first LLM response (question or spec signal)
  - [x] `respond/2` — loads session + message history, appends user message, re-assembles prompt, calls LLM, persists, returns next response
  - [x] `resume/1` — loads session by ID, loads all messages, returns last state (last assistant message + session metadata)
  - [x] Intent clarity is prompt-instructed: the system prompt tells the LLM to gauge clarity and adjust question count
  - [x] Each LLM call includes tool definitions for knowledge queries (so tool_calls are logged for later verification in Story 3.2)
  - [x] Tests: Mox LLM with scripted responses, verify message persistence, verify context is fetched before first question, verify resume loads history

- [x] Task 5: Phoenix Channel for planning transport (AC: #4)
  - [x] Create `FamiliarWeb.PlanningChannel` joining on `"planning:lobby"`
  - [x] Handle `"start_plan"` event — calls Engine.start_plan, pushes response
  - [x] Handle `"respond"` event — calls Engine.respond, pushes response
  - [x] Handle `"resume"` event — calls Engine.resume, pushes session state
  - [x] Add channel route to `FamiliarWeb.UserSocket`
  - [x] Tests: channel tests with Phoenix.ChannelTest, Mox LLM

- [x] Task 6: CLI integration for `fam plan` (AC: #1, #3, #4)
  - [x] Add `plan` command to CLI.Main with args: description (positional), `--resume` (flag), `--session` (integer ID)
  - [x] `fam plan "description"` — calls Engine.start_plan, returns first LLM response
  - [x] `fam plan --resume` — resumes latest active session
  - [x] `fam plan --resume --session 42` — resumes specific session
  - [x] Update `fam search` to use Librarian by default, add `--raw` flag
  - [x] Tests: CLI parse_args for plan command, mock HTTP/Channel interactions

- [x] Task 7: Planning public API update (AC: #1, #3)
  - [x] Update `Familiar.Planning` context module with real implementations delegating to Engine
  - [x] `start_plan/1` -> `Engine.start_plan/2`
  - [x] `respond/2` -> `Engine.respond/2`
  - [x] Add `resume/1` -> `Engine.resume/1`
  - [x] Update Boundary deps if needed
  - [x] Tests: verify delegation, error propagation

### Review Findings

- [x] [Review][Decision] D1: Tool calls declared but never dispatched — deferred to Story 3.2 with comment [engine.ex]
- [x] [Review][Decision] D2: CLI bypasses Phoenix Channel — documented as intentional (CLI in-process, Channel for external) [engine.ex, planning_channel.ex]
- [x] [Review][Decision] D3: insert_message swallows persistence errors — documented as intentional best-effort [engine.ex]
- [x] [Review][Decision] D4: Initial user description persisted as first message, PromptAssembly now takes context+history only [engine.ex, prompt_assembly.ex]
- [x] [Review][Patch] P1: SecretFilter applied to all planning messages via insert_message [engine.ex]
- [x] [Review][Patch] P2: Context persisted on session, reloaded in respond via call_llm(session) [engine.ex, session.ex, migration]
- [x] [Review][Patch] P3: CLI resume uses explicit branching — separate nil/integer paths [cli/main.ex]
- [x] [Review][Patch] P4: Channel DI via Application.get_env + happy-path tests added [planning_channel.ex, planning_channel_test.exs]
- [x] [Review][Patch] P5: Librarian reply tagged with pid — `{:librarian_result, ^pid, result}` [librarian.ex]
- [x] [Review][Patch] P6: Session description validate_length(min: 1, max: 4000) [session.ex]
- [x] [Review][Patch] P7: @gap_threshold module attribute with documentation [librarian.ex]
- [x] [Review][Patch] P8: Lifecycle test uses dedicated DynamicSupervisor + 3 sequential queries [librarian_test.exs]
- [x] [Review][Patch] P9: Actual hop counter threaded through multi_hop_search [librarian.ex]
- [x] [Review][Patch] P10: All Engine status returns normalized to atoms via normalize_status/1 [engine.ex]
- [x] [Review][Patch] P11: Knowledge.search receives only relevant opts via Keyword.take [librarian.ex]
- [x] [Review][Patch] P12: Migration uses timestamps(type: :utc_datetime, updated_at: false) [migration]
- [x] [Review][Patch] P13: LLM call budget documented in @moduledoc [librarian.ex]
- [x] [Review][Defer] W1: UserSocket has no authentication — acceptable for local-only dev tool, defer to multi-user story [user_socket.ex] — deferred, pre-existing architectural decision

## Dev Notes

### Architecture Constraints

- **Hexagonal architecture**: All LLM calls go through `Providers.chat/2` (backed by `Familiar.Providers.LLM` behaviour, Mox in tests). All knowledge queries through `Knowledge.search/1` or `Librarian.query/1`.
- **6 behaviour ports**: LLM, FileSystem, Shell, Notifications, Clock, Embedder — all Mox-mockable.
- **Error tuples**: All public functions return `{:ok, result}` or `{:error, {atom, map}}`. Follow this pattern exactly.
- **PubSub**: `Phoenix.PubSub` available as `Familiar.PubSub`. Use for streaming events in Story 3.3 — this story focuses on the request/response engine.
- **Task.Supervisor**: Background work goes through `Familiar.TaskSupervisor` (already in supervision tree).
- **DynamicSupervisor**: Add `Familiar.LibrarianSupervisor` to supervision tree for ephemeral Librarian GenServers.

### Existing Code to Reuse

| Module | API | Use For |
|--------|-----|---------|
| `Knowledge.search/1` | `search(query, opts)` -> `{:ok, [map]}` | Raw knowledge retrieval (used by Librarian internally) |
| `Knowledge.search_by_vector/2` | `search_by_vector(vector, opts)` -> `{:ok, [map]}` | Alternative search with pre-computed vector |
| `Providers.chat/2` | `chat(messages, opts)` -> `{:ok, map}` | LLM calls for planning conversation and Librarian summarization |
| `Providers.stream_chat/2` | `stream_chat(messages, opts)` -> `{:ok, Enumerable.t}` | Streaming LLM (for Story 3.3, not this story) |
| `Providers.embed/1` | `embed(text)` -> `{:ok, [float]}` | Text embedding (used by Knowledge.search internally) |
| `Knowledge.SecretFilter.filter/1` | `filter(text)` -> string | Filter secrets from any text before persistence |
| `Familiar.Repo` | Ecto repo with SQLite | All database operations via Ecto sandbox in tests |

### Librarian Agent Design

The Librarian is the **key architectural addition** in this story. Design principles:
- **Ephemeral**: `GenServer.start_link` -> do work -> `GenServer.stop(self())`. No state survives between queries.
- **Multi-hop**: Initial search -> evaluate coverage -> if gaps, refine terms and re-search (max 3 iterations). Prevents tunnel vision on first-hit results.
- **Summarization**: LLM call to distill raw search results into a concise, cited context block. This saves tokens in the planning engine's context window.
- **DI-friendly**: Accept opts for `:knowledge_mod` and `:llm_mod` to allow Mox injection.
- The GenServer is a coordination mechanism, not a persistence mechanism. It ensures the multi-hop cycle completes atomically and provides a clean API boundary.

### Prompt Assembly Design

`Planning.PromptAssembly` is the **critical pure-function module** (100% coverage required). It transforms:
- `description` (user's feature request)
- `context_block` (Librarian's curated summary)
- `conversation_history` (list of `%{role, content}` from planning_messages)

Into:
- `system_prompt` — instructions for the LLM: adaptive depth, citation format, no repeats, edge case surfacing
- `messages` — properly formatted message list for `Providers.chat/2`

This is a pure function with no side effects — test extensively with property tests.

### Conversation Persistence

Planning messages stored in SQLite via Ecto:
- `planning_sessions` table: id, description, status, timestamps
- `planning_messages` table: id, session_id (FK), role, content, tool_calls (JSON text), inserted_at
- Messages are append-only during a session
- Resume loads all messages for a session, re-assembles prompt, continues

### Phoenix Channel Transport

The CLI connects to the daemon's Phoenix endpoint via WebSocket. This reuses the existing Phoenix infrastructure (`FamiliarWeb.Endpoint`). The channel provides bidirectional streaming — critical for the interactive conversation loop where the user and LLM take turns.

### CLI Interactive Loop

`fam plan` enters an interactive stdin loop:
1. Connect to WebSocket channel
2. Send `start_plan` with description
3. Receive LLM response (question or spec-ready signal)
4. Print question, read user input from stdin
5. Send `respond` with user input
6. Repeat until spec signal received
7. On spec signal, hand off to Story 3.2 (spec generation)

For this story, the "spec signal" is simply the LLM indicating it has enough information. The actual spec generation is Story 3.2.

### Project Structure Notes

New files to create (aligned with architecture.md):
```
familiar/lib/familiar/planning/
├── planning.ex              # Already exists — update stubs to delegate
├── engine.ex                # Planning conversation engine
├── prompt_assembly.ex       # Pure function: context → prompt
├── session.ex               # Ecto schema for planning_sessions
├── message.ex               # Ecto schema for planning_messages
└── librarian.ex             # Ephemeral GenServer for curated retrieval

familiar/lib/familiar_web/channels/
├── user_socket.ex           # May already exist — add planning channel route
└── planning_channel.ex      # Phoenix Channel for planning transport

familiar/priv/repo/migrations/
├── *_create_planning_sessions.exs
└── *_create_planning_messages.exs

familiar/test/familiar/planning/
├── engine_test.exs
├── prompt_assembly_test.exs
├── librarian_test.exs
├── session_test.exs
└── message_test.exs

familiar/test/familiar_web/channels/
└── planning_channel_test.exs
```

### Previous Story Intelligence

**From Epic 2 (Story 2.7 and retrospective):**
- **DI Clock pattern**: When tests depend on timestamps, inject Clock behaviour via `Application.get_env(:familiar, Familiar.System.Clock, Familiar.System.RealClock)`. Use this for session timestamps.
- **Single-embed optimization**: Embed once, pass vector through pipeline. Applied in hygiene; same pattern applies if Librarian needs to embed query terms.
- **Defense-in-depth filtering**: Run `SecretFilter.filter/1` on any user-provided text before persisting (planning messages may contain sensitive project details).
- **Mox pattern**: All tests use `Mox.expect(Familiar.Providers.MockLLM, :chat, fn msgs, _opts -> ... end)`. Follow existing test setup in `test/support/data_case.ex`.
- **Task.Supervisor**: Background work uses `Task.Supervisor.start_child(Familiar.TaskSupervisor, fn -> ... end)`. Do not use bare `Task.start`.
- **sqlite-vec subquery pattern**: For searching by existing embedding, use `WHERE embedding MATCH (SELECT embedding FROM ... WHERE entry_id = ?)`.
- **Test count baseline**: 530 tests + 4 properties, 0 failures. Credo strict: 0 issues. Do not regress.

**From Epic 2 deferred items (all resolved):**
- N+1 query in consolidation is a known sqlite-vec limitation (capped at 5000 entries). Not relevant to this story but good to know about query patterns.

### Testing Standards

- **Mox for all behaviours**: LLM, FileSystem, Shell, Notifications, Clock, Embedder
- **Ecto sandbox**: `use Familiar.DataCase, async: true` where possible, `async: false` for shared state
- **Property tests**: Required for `Planning.PromptAssembly` — verify output structure invariants across random inputs
- **100% coverage**: `Planning.PromptAssembly` (critical module)
- **Near-100% coverage**: Engine, Librarian, Channel
- **Integration test**: Deferred to Story 3.7, but unit tests should be thorough enough to catch regressions
- **No `@tag :skip`**: All tests must pass

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 3, Story 3.1]
- [Source: _bmad-output/planning-artifacts/architecture.md — Planning context, lines 776-782]
- [Source: _bmad-output/planning-artifacts/prd.md — FR20-FR22, FR30]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Planning journey, streaming trail]
- [Source: .claude/projects/.../memory/project_librarian_agent.md — Librarian Agent pattern]
- [Source: _bmad-output/implementation-artifacts/epic-2-retro-2026-04-02.md — Deferred items, Librarian discovery]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Task 1: Created planning_sessions and planning_messages migrations + Ecto schemas. 17 tests (changeset validation, persistence, cascade delete, FK constraints).
- Task 2: Librarian Agent — ephemeral GenServer under DynamicSupervisor with multi-hop retrieval (max 3), LLM summarization, and DI for testing. 6 tests. `fam search` now routes through Librarian by default; `--raw` bypasses.
- Task 3: PromptAssembly pure function module — assembles system prompt + messages from description, context, and history. Adaptive depth, citation, no-repeat, and [SPEC_READY] signal instructions. 13 tests + 4 property tests (100% coverage target).
- Task 4: Planning Engine — start_plan/respond/resume lifecycle with session and message persistence in SQLite. Librarian context fetch, prompt assembly, LLM chat, tool_call logging. 16 tests.
- Task 5: Phoenix Channel on "planning:lobby" — start_plan, respond, resume events. UserSocket with channel routing. 6 channel tests.
- Task 6: CLI — `fam plan <description>`, `--resume`, `--session`, `--raw` search. Help text updated. 10 new CLI tests (4 parse_args + 4 plan + 2 librarian search).
- Task 7: Planning context API updated from stubs to real Engine delegation. 5 delegation tests.
- Total: 73 new tests + 4 new property tests. Full suite: 603 tests + 8 properties, 0 failures. Credo strict: 0 issues.

### Change Log

- 2026-04-02: Story 3.1 implemented — Planning Conversation Engine with Librarian Agent, PromptAssembly, Engine, Channel, CLI integration

### File List

- familiar/priv/repo/migrations/20260402200000_create_planning_sessions.exs (new)
- familiar/priv/repo/migrations/20260402200001_create_planning_messages.exs (new)
- familiar/lib/familiar/planning/session.ex (new)
- familiar/lib/familiar/planning/message.ex (new)
- familiar/lib/familiar/planning/librarian.ex (new)
- familiar/lib/familiar/planning/prompt_assembly.ex (new)
- familiar/lib/familiar/planning/engine.ex (new)
- familiar/lib/familiar/planning/planning.ex (modified — stubs replaced with Engine delegation)
- familiar/lib/familiar/application.ex (modified — added LibrarianSupervisor)
- familiar/lib/familiar_web/endpoint.ex (modified — added /socket for UserSocket)
- familiar/lib/familiar_web/channels/user_socket.ex (new)
- familiar/lib/familiar_web/channels/planning_channel.ex (new)
- familiar/lib/familiar/cli/main.ex (modified — plan command, --raw search, librarian search)
- familiar/test/familiar/planning/session_test.exs (new)
- familiar/test/familiar/planning/message_test.exs (new)
- familiar/test/familiar/planning/librarian_test.exs (new)
- familiar/test/familiar/planning/prompt_assembly_test.exs (new)
- familiar/test/familiar/planning/engine_test.exs (new)
- familiar/test/familiar/planning/planning_test.exs (new)
- familiar/test/familiar_web/channels/planning_channel_test.exs (new)
- familiar/test/support/channel_case.ex (new)
- familiar/test/familiar/cli/main_test.exs (modified — plan + librarian search tests, raw flag on existing search tests)
