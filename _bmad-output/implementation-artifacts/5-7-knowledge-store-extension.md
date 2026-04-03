# Story 5.7: Knowledge Store Extension

Status: done

## Story

As a developer building the harness,
I want the existing Knowledge Store wrapped as an extension implementing the Extension behaviour,
So that it registers tools and hooks like any other extension and can be replaced or augmented.

## Acceptance Criteria

### AC1: Extension Module Implementing `Familiar.Extension` Behaviour

**Given** the `Familiar.Extension` behaviour exists (Story 5.1)
**When** `Familiar.Extensions.KnowledgeStore` is implemented
**Then** it implements all required callbacks: `name/0`, `tools/0`, `hooks/0`, `init/1`
**And** `name/0` returns `"knowledge-store"`
**And** `tools/0` returns registrations for `:search_context` and `:store_context`
**And** `hooks/0` returns event hooks for `:on_agent_complete` and `:on_file_changed`
**And** `init/1` returns `:ok` (no special initialization needed — Knowledge context already started by Repo)

### AC2: `search_context` Tool

**Given** the extension is loaded and tools are registered
**When** an agent calls `:search_context` with `%{query: "some query"}`
**Then** it delegates to `Familiar.Knowledge.search/2`
**And** returns `{:ok, results}` with a list of result maps (id, text, type, source, distance, freshness)
**And** returns `{:ok, []}` for empty or whitespace-only queries
**And** returns `{:error, reason}` on failure (embedding unavailable, etc.)

### AC3: `store_context` Tool

**Given** the extension is loaded and tools are registered
**When** an agent calls `:store_context` with `%{text: "...", type: "fact", source: "agent"}`
**Then** it delegates to `Familiar.Knowledge.store/1`
**And** returns `{:ok, %{id: id, text: text, type: type}}` on success
**And** existing validations apply: secret filtering, content validation (rejects code), type/source validation
**And** returns `{:error, reason}` on validation failure

### AC4: `on_agent_complete` Event Hook

**Given** the extension is loaded and hooks are registered
**When** an agent completes (`:on_agent_complete` event fires)
**Then** the handler triggers `Familiar.Knowledge.Hygiene.run/2` with the event payload
**And** the hygiene run is fire-and-forget (async, does not block the event)
**And** failures in hygiene are logged but do not propagate

### AC5: `on_file_changed` Event Hook

**Given** the extension is loaded and hooks are registered
**When** a file change event fires (`:on_file_changed` with `%{path: ..., type: ...}`)
**Then** the handler triggers freshness invalidation for knowledge entries sourced from that file
**And** for `:deleted` events, entries with that `source_file` are marked for removal
**And** for `:changed` events, entries with that `source_file` are marked stale
**And** the handler is fire-and-forget (does not block the file watcher)
**And** failures are logged but do not propagate

### AC6: Extension Config Registration

**Given** the application starts
**When** `config :familiar, :extensions` includes `Familiar.Extensions.KnowledgeStore`
**Then** it loads via `ExtensionLoader` after Safety
**And** its tools override the builtin stubs (if any) in the ToolRegistry
**And** its hooks are registered at default priority (100)
**And** disabled in test env (`config :familiar, :extensions, []` in test.exs)

### AC7: Test Coverage

**Given** `Familiar.Extensions.KnowledgeStore` is implemented
**When** `mix test` runs
**Then** tests cover: behaviour callbacks, search_context tool (valid query, empty query, error), store_context tool (valid store, validation failure), on_agent_complete hook handler, on_file_changed hook handler (changed/deleted), extension registration contract
**And** tests mock LLM/Embedder (existing Mox pattern)
**And** Credo strict passes with 0 issues
**And** no regressions in existing test suite (831 tests + 5 properties baseline)

## Tasks / Subtasks

- [x] Task 1: Create `Familiar.Extensions.KnowledgeStore` module (AC: 1, 6)
  - [x] Create `lib/familiar/extensions/knowledge_store.ex`
  - [x] Implement `Familiar.Extension` behaviour callbacks
  - [x] `name/0` → `"knowledge-store"`
  - [x] `tools/0` → `[{:search_context, &search_context/2, desc}, {:store_context, &store_context/2, desc}]`
  - [x] `hooks/0` → event hooks for `:on_agent_complete` (priority 100) and `:on_file_changed` (priority 100)
  - [x] `init/1` → `:ok` (no special init needed)

- [x] Task 2: Implement `search_context/2` tool function (AC: 2)
  - [x] Extract `query` from args (support atom and string keys)
  - [x] Extract optional `limit` from args
  - [x] Delegate to `Familiar.Knowledge.search/2`
  - [x] Return `{:ok, results}` or `{:error, reason}`

- [x] Task 3: Implement `store_context/2` tool function (AC: 3)
  - [x] Extract `text`, `type`, `source` from args (support atom and string keys)
  - [x] Optionally extract `source_file`, `metadata`
  - [x] Delegate to `Familiar.Knowledge.store/1`
  - [x] Return `{:ok, %{id: ..., text: ..., type: ...}}` or `{:error, reason}`

- [x] Task 4: Implement `on_agent_complete` event handler (AC: 4)
  - [x] Handler receives `%{agent_id: ..., role: ..., result: ...}` payload
  - [x] Spawn async task via `Task.Supervisor` to run `Hygiene.run/2`
  - [x] Build hygiene context from event payload
  - [x] Log and swallow errors (fire-and-forget)

- [x] Task 5: Implement `on_file_changed` event handler (AC: 5)
  - [x] Handler receives `%{path: ..., type: :created | :changed | :deleted}` payload
  - [x] Query entries with matching `source_file`
  - [x] For `:deleted` → delete matching entries via `Knowledge.delete_entry/1`
  - [x] For `:changed` → trigger freshness refresh for matching entries
  - [x] Spawn async — do not block the file watcher event dispatch
  - [x] Log and swallow errors
  - [x] Handle unexpected payload shape gracefully

- [x] Task 6: Add to extension config (AC: 6)
  - [x] Add `Familiar.Extensions.KnowledgeStore` to `config :familiar, :extensions` in `config.exs`
  - [x] Add to `Familiar.Extensions` boundary exports (with `Familiar.Knowledge` dep)

- [x] Task 7: Tests (AC: 7)
  - [x] Create `test/familiar/extensions/knowledge_store_test.exs`
  - [x] Test: name/0 returns "knowledge-store"
  - [x] Test: tools/0 returns search_context and store_context registrations
  - [x] Test: hooks/0 returns on_agent_complete and on_file_changed event hooks
  - [x] Test: search_context with valid query returns results
  - [x] Test: search_context with empty query returns []
  - [x] Test: search_context with nil query returns []
  - [x] Test: search_context with string keys
  - [x] Test: search_context error when embedding fails
  - [x] Test: store_context with valid attrs creates entry
  - [x] Test: store_context with string keys
  - [x] Test: store_context with invalid type returns error
  - [x] Test: store_context with missing text returns error
  - [x] Test: store_context with optional source_file/metadata
  - [x] Test: on_agent_complete handler triggers hygiene (fire-and-forget)
  - [x] Test: on_agent_complete with nil result
  - [x] Test: on_file_changed with :deleted removes entries
  - [x] Test: on_file_changed with :deleted doesn't affect other files
  - [x] Test: on_file_changed with :changed triggers refresh
  - [x] Test: on_file_changed with unexpected payload
  - [x] Test: hooks registration contract with Hooks GenServer
  - [x] Test: tool functions have correct arity

- [x] Task 8: Credo, formatting, full regression (AC: 7)
  - [x] `mix format` passes
  - [x] `mix credo --strict` passes with 0 issues
  - [x] Full test suite passes with 0 failures (855 tests + 5 properties)

### Review Findings

- [x] [Review][Decision] Direct `Repo.all` in extension bypasses Knowledge context — added `Knowledge.list_by_source_file/1` public function and updated extension to delegate through it. Removed `Repo`/`Entry`/`Ecto.Query` imports from extension
- [x] [Review][Patch] `put_if_present` dropped falsy values (`false`, `0`) — changed from `if value` to `if is_nil(value)` so only nil is treated as absent [knowledge_store.ex:154]
- [x] [Review][Patch] `search_context` with non-string query crashes `String.trim` — added `is_binary(query)` guard, non-strings coerced to `""` [knowledge_store.ex:58]
- [x] [Review][Patch] `build_hygiene_context` discarded payload fields hygiene expects — now passes full payload as `success_context` so task_summary, modified_files etc. are available [knowledge_store.ex:157-159]
- [x] [Review][Patch] `extract_search_opts` always returned `[]` — rewrote to return `[limit: limit]` directly instead of rebinding [knowledge_store.ex:137-139]
- [x] [Review][Patch] `process_file_event(:deleted)` had no error handling — now collects results, counts failures, logs warning [knowledge_store.ex:116-126]
- [x] [Review][Patch] No test for `:created` event type — added test for created event with existing entries
- [x] [Review][Patch] `:changed` test didn't assert entry survives — now asserts `Repo.get != nil` after refresh
- [x] [Review][Patch] Non-string query test added — verifies integer and boolean queries don't crash
- [x] [Review][Defer] `extract_search_opts` limit never reaches `search_similar` — `Knowledge.search_inner` calls `search_similar(query)` without forwarding opts. Pre-existing Knowledge context issue, not extension bug
- [x] [Review][Defer] Double-spawn maintenance for same stale entries — race in `Knowledge.trigger_background_maintenance`, pre-existing
- [x] [Review][Defer] Negative/non-integer limit not validated — deferred to input validation story

## Dev Notes

### Architecture Constraints

- **Extension, NOT core** — KnowledgeStore is a default extension like Safety. Loads via `ExtensionLoader`, not the supervision tree. [Source: architecture.md line 1796-1801]
- **Thin wrapper** — This story wraps existing `Familiar.Knowledge` functions. Does NOT reimplement search, storage, freshness, or hygiene. All that code exists from Epic 2.
- **No child_spec needed** — Knowledge context is already started (Repo, PubSub). The extension just registers tools and hooks. No additional supervised processes needed.
- **Event hooks at priority 100** — Default priority. Safety runs at 1 (alter), knowledge hooks are event-only (priority not used for dispatch order, only for alter pipeline).

### Existing Knowledge API to Wrap

```elixir
# search_context delegates to:
Familiar.Knowledge.search(query, opts)
# Returns {:ok, [%{id, text, type, source, source_file, distance, freshness}]}

# store_context delegates to:
Familiar.Knowledge.store(%{text: ..., type: ..., source: ..., source_file: ..., metadata: ...})
# Returns {:ok, %Entry{}} or {:error, {:validation_failed, %{...}}}
```

### Event Payloads

```elixir
# on_agent_complete (from AgentProcess)
%{agent_id: String.t(), role: String.t(), result: String.t()}

# on_file_changed (from FileWatcher)
%{path: String.t(), type: :created | :changed | :deleted}
```

### Tool Function Contract

Tool functions receive `(args :: map(), context :: map())` and return `{:ok, result}` or `{:error, reason}`. The `context` contains `%{agent_id: ..., role: ..., conversation_id: ...}`.

### File Changed Handler Strategy

For `:deleted` events:
```elixir
import Ecto.Query
entries = Repo.all(from e in Entry, where: e.source_file == ^path)
Enum.each(entries, &Knowledge.delete_entry/1)
```

For `:changed` events — trigger freshness refresh:
```elixir
entries = Repo.all(from e in Entry, where: e.source_file == ^path)
Freshness.refresh_stale(entries, opts)
```

### Test Strategy

Tests need database access (knowledge entries in SQLite) so use `Ecto.Adapters.SQL.Sandbox`. Mock the LLM/Embedder via existing Mox pattern:
```elixir
import Mox
setup :verify_on_exit!

Familiar.Knowledge.EmbedderMock
|> expect(:embed, fn text -> {:ok, List.duplicate(0.0, 384)} end)
```

For event handler tests, call the handler function directly and verify side effects via database queries.

### Existing Patterns to Follow

- **Extension implementation**: `Familiar.Extensions.Safety` — same module structure
- **Knowledge API tests**: `test/familiar/knowledge/` — patterns for mocking embedder, creating entries
- **Event handler tests**: call handler directly, verify DB state
- **Boundary exports**: Add to `Familiar.Extensions` boundary in `extensions.ex`

### Previous Story Intelligence (Story 5.6)

- Safety extension used ETS for config. KnowledgeStore doesn't need config — it delegates directly to Knowledge context functions.
- Extension loader calls `init/1` once at startup. Simple `:ok` return is fine.
- Tests should be `async: false` if sharing DB state (Ecto sandbox mode).
- Credo strict: 0 issues. Test baseline: 831 tests + 5 properties.
- Event hooks are fire-and-forget — handler receives single `(payload)` arg (arity 1), not `(payload, context)`.

### Deferred Items (NOT in scope)

- **`after_tool_call` hook** — Architecture mentions KS subscribing to `after_tool_call` for knowledge capture from tool outputs. This requires parsing tool results for knowledge-worthy content — complex LLM step. Defer to a future enhancement story.
- **TOML config** — `.familiar/config.toml` `[knowledge]` section. No TOML parser exists. Use opts for now.
- **Embedding worker pool supervision** — Architecture mentions child_spec for embedding pool. The existing `Task.Supervisor` is already used. No additional supervision needed.
- **`list_entries`, `check_freshness`, `knowledge_health`** — Architecture mentions additional tools. Only `search_context` and `store_context` are MVP scope per epics. Others can be added later.

### Project Structure Notes

New files:
```
lib/familiar/extensions/
├── knowledge_store.ex     # NEW — KnowledgeStore extension module

test/familiar/extensions/
├── knowledge_store_test.exs  # NEW — KnowledgeStore extension tests
```

Modified files:
```
familiar/config/config.exs                      # MODIFIED — add KnowledgeStore to :extensions
familiar/lib/familiar/extensions/extensions.ex   # MODIFIED — add KnowledgeStore to boundary exports
```

### References

- [Source: architecture.md line 1796-1801 — Default extensions table (KS has tools + hooks)]
- [Source: architecture.md line 1784-1792 — Event hooks: after_tool_call, on_agent_complete, on_file_changed]
- [Source: architecture.md line 1418-1420 — search_context and store_context tool definitions]
- [Source: epics.md line 1306-1312 — Story 5.7 scope definition]
- [Source: knowledge.ex — search/2 and store/1 public API]
- [Source: hygiene.ex — Hygiene.run/2 post-task capture]
- [Source: freshness.ex — Freshness.refresh_stale/2 and validate_entries/2]
- [Source: safety.ex — Extension implementation pattern]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- KnowledgeStore extension wrapping existing `Familiar.Knowledge` context as thin adapter
- Two tools: `:search_context` (delegates to `Knowledge.search/2`) and `:store_context` (delegates to `Knowledge.store/1`)
- Two event hooks: `:on_agent_complete` (triggers `Hygiene.run/2` async) and `:on_file_changed` (deletes/refreshes entries)
- All event handlers fire-and-forget via `Task.Supervisor.start_child` — errors logged, never propagate
- File change handler uses pattern-matched `process_file_event/3` helpers to avoid nesting
- Supports both atom and string keys in tool args (LLM may send either)
- `normalize_store_attrs/1` extracts known fields, ignoring unknowns
- Boundary updated: `Familiar.Extensions` depends on `Familiar.Knowledge`
- Credo strict: 0 issues (fixed nesting depth, length/1 comparison)
- 22 new tests; 853 total tests + 5 properties, 0 failures, 0 regressions

### File List

- `familiar/lib/familiar/extensions/knowledge_store.ex` — NEW: KnowledgeStore extension module
- `familiar/test/familiar/extensions/knowledge_store_test.exs` — NEW: 22 extension tests
- `familiar/config/config.exs` — MODIFIED: add KnowledgeStore to `:extensions` list
- `familiar/lib/familiar/extensions/extensions.ex` — MODIFIED: add KnowledgeStore export + Knowledge dep
