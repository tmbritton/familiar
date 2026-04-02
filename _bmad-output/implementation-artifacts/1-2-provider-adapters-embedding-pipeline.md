# Story 1.2: Provider Adapters & Embedding Pipeline

Status: done

## Story

As a developer,
I want Familiar to connect to Ollama for LLM inference and embedding generation,
so that the system can extract knowledge from code and store it as searchable vectors.

## Acceptance Criteria

1. **Ollama LLM Adapter:** Ollama LLM adapter implements `Familiar.Providers.LLM` behaviour. `chat/2` returns structured response. `stream_chat/2` returns an `Enumerable.t()` of events normalized to common format (`{:text_delta, binary()}`, `{:tool_call_delta, map()}`, `{:done, %{content, tool_calls, usage}}`).
2. **Ollama Embedder Adapter:** Ollama embedder adapter implements `Familiar.Knowledge.Embedder` behaviour. `embed/1` returns a float vector that can be stored in sqlite-vec and retrieved by cosine similarity.
3. **Provider Auto-Detection:** System detects whether Ollama is running at `localhost:11434`, reports available models (embedding + coding), and returns clear error if Ollama is unavailable.
4. **Embedding Pipeline:** When text is embedded via the pipeline, the vector is stored in a sqlite-vec column and retrievable by semantic similarity query. Retrieval completes within 2 seconds for 200+ entries (NFR1).
5. **Providers Facade Wired:** `Familiar.Providers.chat/2`, `stream_chat/2`, and `embed/1` delegate to configured adapters via `Application.get_env` resolution (Mox in test, Ollama in prod/dev).
6. **Testing:** All adapter behaviour callbacks covered with Mox unit tests. Streaming normalization tested with scripted NDJSON responses. Property-based contract tests via StreamData. Integration tests tagged `:integration`.

## Tasks / Subtasks

- [x] Task 1: Add dependency and create StreamEvent module (AC: #1, #5)
  - [x] Skipped `ollama` hex package — used raw `req` (already a dependency) per architecture escape hatch. Ollama API is 3 endpoints; adding a wrapper library that wraps Req adds unnecessary indirection.
  - [x] Create `lib/familiar/providers/stream_event.ex` — `Familiar.Providers.StreamEvent` module with `@type t()` covering all 4 stream event variants
- [x] Task 2: Create Ollama LLM adapter (AC: #1)
  - [x] Create `lib/familiar/providers/ollama_adapter.ex` — `Familiar.Providers.OllamaAdapter`
  - [x] Implement `@behaviour Familiar.Providers.LLM`
  - [x] Implement `chat/2`: calls Ollama `/api/chat` with `stream: false`
  - [x] Implement `stream_chat/2`: calls Ollama `/api/chat` with `stream: true`, returns `{:ok, Stream.resource(...)}`
  - [x] Handle NDJSON parsing with line buffering (TCP chunks may split JSON lines)
  - [x] Normalize Ollama events to `StreamEvent.t()` format
  - [x] Map errors: connection refused, 404 (model not found), timeout
  - [x] Support `model`, `receive_timeout`, and `options` in opts
- [x] Task 3: Create Ollama Embedder adapter (AC: #2)
  - [x] Create `lib/familiar/providers/ollama_embedder.ex` — `Familiar.Providers.OllamaEmbedder`
  - [x] Implement `@behaviour Familiar.Knowledge.Embedder`
  - [x] Implement `embed/1`: calls Ollama `POST /api/embed`, returns `{:ok, [float()]}`
  - [x] Handles empty embeddings, model not found, connection errors
  - [x] Configurable embedding model via `:ollama` app config
- [x] Task 4: Create provider auto-detection module (AC: #3)
  - [x] Create `lib/familiar/providers/detector.ex` — `Familiar.Providers.Detector`
  - [x] `detect/0`: GET health check with 2s timeout
  - [x] `list_models/0`: GET /api/tags with 5s timeout
  - [x] `check_prerequisites/0`: validates Ollama running + chat model + embedding model available
  - [x] Model matching supports both exact name and name:tag format
  - [x] Base URL configurable via `:ollama` app config
- [x] Task 5: Wire Providers facade to delegate to adapters (AC: #5)
  - [x] `chat/2`, `stream_chat/2`, `embed/1` delegate via `Application.get_env`
  - [x] Added `detect/0`, `list_models/0`, `check_prerequisites/0` via `defdelegate` to Detector
- [x] Task 6: Create knowledge_entries Ecto schema and migration (AC: #4)
  - [x] Migration creates `knowledge_entries` table with text, type, source, source_file, metadata, timestamps
  - [x] Migration creates `knowledge_entry_embeddings` vec0 virtual table (768 dimensions)
  - [x] `Familiar.Knowledge.Entry` schema with changeset validating required fields and type/source inclusion
  - [x] Indexes on type, source, source_file
- [x] Task 7: Create embedding pipeline — store and retrieve (AC: #4)
  - [x] `store_with_embedding/1`: validate → insert entry → embed text → store vector
  - [x] `search_similar/2`: embed query → vec0 MATCH → load entries → sort by distance
  - [x] Vectors passed as JSON array strings per Story 1.1a learning
- [x] Task 8: Configure production adapters (AC: #5)
  - [x] `config/config.exs`: LLM → OllamaAdapter, Embedder → OllamaEmbedder
  - [x] Ollama config: base_url, chat_model, embedding_model, receive_timeout
  - [x] `config/test.exs` mock config takes precedence (already set in 1.1b)
- [x] Task 9: Write unit tests with Mox mocks (AC: #6)
  - [x] `ollama_adapter_test.exs`: 9 tests — NDJSON parsing (4), event normalization (5)
  - [x] `ollama_embedder_test.exs`: 3 tests — embed success, connection error, model not found
  - [x] `detector_test.exs`: 3 integration-tagged tests
  - [x] `providers_test.exs`: 5 tests — facade delegation for chat, stream_chat, embed
  - [x] `entry_test.exs`: 9 tests — changeset validation for all fields and constraints
- [x] Task 10: Write embedding pipeline tests (AC: #4, #6)
  - [x] `embedding_pipeline_test.exs`: 8 tests — store + retrieve + ranking + limits + errors
  - [x] Uses `async: false` for sqlite-vec virtual table tests
  - [x] Uses real SQLite + sqlite-vec for vector operations, Mox for embedder
- [x] Task 11: Write property-based contract tests (AC: #6)
  - [x] `provider_contract_test.exs`: 4 properties — LLM chat contract (2), Embedder contract (2)
  - [x] StreamData generators for messages, text inputs
  - [x] Verifies return type contracts and consistent dimensionality
- [x] Task 12: Write integration tests (AC: #6)
  - [x] `ollama_integration_test.exs`: 6 tests tagged `:integration`
  - [x] Tests real Ollama chat, stream_chat, embed, detect, list_models, check_prerequisites
  - [x] `ExUnit.configure(exclude: [:integration])` added to test_helper.exs
- [x] Task 13: Final verification (AC: all)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix test` — 62 tests + 4 properties, 0 failures (9 integration excluded)
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — no issues
  - [x] Boundary checks pass

### Review Findings

- [x] [Review][Decision] D1: `ollama ~> 0.9` dependency dropped in favor of raw Req — Approved by project owner. Raw Req is acceptable.
- [x] [Review][Patch] P1: `store_with_embedding/1` orphans DB row when embedding fails — Fixed: added compensating `Repo.delete` on embed/insert failure via `embed_or_rollback/1` and `insert_embedding_or_rollback/2`.
- [x] [Review][Patch] P2: `spawn_link` in `stream_chat/2` crashes caller — Fixed: changed to `spawn` with `try/rescue` wrapper.
- [x] [Review][Patch] P3: Stream process not cleaned up on early halt — Fixed: `cleanup_stream/1` sends `Process.exit(pid, :kill)` in Stream.resource terminator.
- [x] [Review][Patch] P4: `Jason.decode!` in `parse_ndjson` crashes on malformed NDJSON — Fixed: changed to `Jason.decode` with `Enum.flat_map` filtering errors.
- [x] [Review][Patch] P5: `receive_timeout` hardcoded at 120s in stream consumer — Fixed: threaded through stream state from opts.
- [x] [Review][Patch] P6: `impl/1` returns `nil` on missing config — Fixed: raises descriptive error message with config guidance.
- [x] [Review][Patch] P7: `insert_embedding` error misclassified as `:validation_failed` — Fixed: changed to `:storage_failed`. Added to `Error.recoverable?/1` as `false`.
- [x] [Review][Patch] P8: `search_similar` error misclassified as `:not_found` — Fixed: changed to `:query_failed`. Added to `Error.recoverable?/1` as `false`.
- [x] [Review][Patch] P9: `detect/0` calls `base_url()` twice (TOCTOU) — Fixed: captured in variable.
- [x] [Review][Patch] P10: `OllamaEmbedderTest` tests the Mox mock, not the adapter — Fixed: extracted `parse_response/1` as `@doc false` public function; rewrote 8 tests exercising actual adapter logic.
- [x] [Review][Patch] P11: `Detector` has zero unit tests in default suite — Fixed: extracted `has_model?/2` as `@doc false`; added 6 unit tests for model matching logic.
- [x] [Review][Patch] P12: Embedding dimension mismatch unvalidated — Fixed: added `@expected_embedding_dimensions 768` check before insert; returns `{:error, {:storage_failed, %{reason: :dimension_mismatch, ...}}}`.
- [x] [Review][Defer] W1: Tool-call-delta events never emitted in stream normalization — `normalize_event` has no `{:tool_call_delta, ...}` clause. Deferred: Ollama tool calling is out of scope for Story 1.2; architecture notes it for future. [ollama_adapter.ex:131-150]
- [x] [Review][Defer] W2: `metadata` field stored as raw string with no JSON validation — Deferred: Full Knowledge CRUD validation is Epic 2 (Story 2.1) scope. [entry.ex:20]

## Dev Notes

### Architecture Compliance

**Source:** [architecture.md — Provider Interface Decision, Streaming Normalization, Embedding Pipeline]

**Provider Pattern:** The architecture specifies `ollama ~> 0.9` hex package (which uses Req internally). Both LLM and Embedder adapters implement their respective behaviours. The `Familiar.Providers` facade resolves adapters via `Application.get_env(:familiar, BehaviourModule)` — this is the same pattern used for Mox mocks in tests.

**CRITICAL: Adapter owns the streaming translation.** Consumers (planning engine, agent runner, Phoenix Channel) work with the common `StreamEvent.t()` format only. This normalization is the adapter's primary complexity.

**Graceful Degradation:** Three operational modes defined in architecture:
1. **Full mode:** Ollama running, all features work
2. **Degraded mode (no Ollama):** Read-only commands work, write commands fail with clear message
3. **Recovery mode:** Database integrity check fails, auto-restore from backup

### Ollama API Reference

**Chat — `POST /api/chat`:**
- Request: `%{model: "llama3.2", messages: [...], stream: true/false, options: %{temperature: 0.7, num_ctx: 4096}}`
- Streaming: NDJSON lines. Each has `"done": false/true`. Content in `message.content`. Final line includes `prompt_eval_count`, `eval_count` for usage.
- Tool calls: In `message.tool_calls` array. **Tool calling does NOT support streaming** — must use `stream: false` when tools are provided.
- Thinking: With `"think": true`, response includes `message.thinking` field.

**Embed — `POST /api/embed`:**
- Request: `%{model: "nomic-embed-text", input: "text to embed"}`
- Response: `%{"embeddings" => [[0.1, 0.2, ...]], "total_duration" => ...}`
- Always returns array of arrays. For single input, take `hd(embeddings)`.
- Supports batch: `input: ["text1", "text2"]` → `embeddings: [[...], [...]]`
- Dimensions: 768 for `nomic-embed-text`, 1024 for `mxbai-embed-large`

**Tags — `GET /api/tags`:**
- Response: `%{"models" => [%{"name" => "llama3.2:latest", "details" => %{...}}]}`
- Use for auto-detection and model discovery.

**Health — `GET /`:**
- Returns `"Ollama is running"` with 200 if alive.

### sqlite-vec Vector Storage

**CRITICAL LEARNING FROM STORY 1.1a:** Vectors must be passed as JSON array strings (`"[1.0, 0.0, 0.0]"`), NOT binary encoding. The `SqliteVec.Float32` binary encoding does NOT work with the current version.

**Virtual table creation:**
```sql
CREATE VIRTUAL TABLE knowledge_entry_embeddings USING vec0(
  entry_id integer primary key,
  embedding float[768]
)
```

**Insert:** `INSERT INTO knowledge_entry_embeddings(entry_id, embedding) VALUES (?, ?)` with params `[entry_id, Jason.encode!(vector)]`

**Query:** `SELECT entry_id, distance FROM knowledge_entry_embeddings WHERE embedding MATCH ? ORDER BY distance LIMIT ?` with params `[Jason.encode!(query_vector), limit]`

**Async caveat:** sqlite-vec virtual tables don't participate in Ecto sandbox transactions. Tests using virtual tables MUST set `async: false`.

### NDJSON Stream Parsing

Req delivers TCP chunks that may split JSON lines. Buffer pattern required:

```elixir
defp parse_ndjson(buffer, new_data) do
  combined = buffer <> new_data
  lines = String.split(combined, "\n")
  {complete, [remainder]} = Enum.split(lines, -1)
  events = complete |> Enum.reject(&(&1 == "")) |> Enum.map(&Jason.decode!/1)
  {events, remainder}
end
```

### Error Handling Convention

All errors follow `{:error, {atom_type, map_details}}`. Provider errors use:
- `{:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}`
- `{:provider_unavailable, %{provider: :ollama, reason: :model_not_found, model: "..."}}`
- `{:provider_unavailable, %{provider: :ollama, reason: :timeout}}`

These are classified as `recoverable? → true` by `Familiar.Error`.

### Testing Strategy

**Unit tests (default `mix test`):** Mox mocks for LLM and Embedder behaviours. Req.Test adapter or Mox for HTTP layer in adapter tests. Deterministic vectors for embedding pipeline tests. Real SQLite + sqlite-vec for vector operations.

**Property tests:** StreamData generates random valid inputs. Verify adapters never crash on valid input — always return ok/error tuple.

**Integration tests (`mix test --include integration`):** Require running Ollama with models installed. Tagged `@moduletag :integration`. Excluded by default. Test real HTTP calls end-to-end.

**ExUnit config for integration tag exclusion** — verify `test/test_helper.exs` has `ExUnit.configure(exclude: [:integration])`.

### Boundary Configuration

`Familiar.Providers.OllamaAdapter`, `Familiar.Providers.OllamaEmbedder`, `Familiar.Providers.Detector`, and `Familiar.Providers.StreamEvent` all belong to the `Familiar.Providers` boundary context. No new boundary deps needed — Providers depends only on externals (Ollama HTTP).

`Familiar.Knowledge.Entry` belongs to the `Familiar.Knowledge` boundary. Knowledge depends on Providers (for embedding).

### Project Structure After This Story

```
lib/familiar/
├── providers/
│   ├── providers.ex          # MODIFIED — facade delegates to adapters
│   ├── llm.ex                # (from 1.1b — behaviour definition, unchanged)
│   ├── ollama_adapter.ex     # NEW — Ollama LLM adapter
│   ├── ollama_embedder.ex    # NEW — Ollama embedder adapter
│   ├── detector.ex           # NEW — provider auto-detection
│   └── stream_event.ex       # NEW — common stream event types
├── knowledge/
│   ├── knowledge.ex          # MODIFIED — add store_with_embedding/1, search_similar/2
│   ├── embedder.ex           # (from 1.1b — behaviour definition, unchanged)
│   └── entry.ex              # NEW — Ecto schema for knowledge_entries

config/
├── config.exs                # MODIFIED — add production adapter config + Ollama settings
├── test.exs                  # (from 1.1b — mock config, unchanged)

priv/repo/migrations/
├── YYYYMMDDHHMMSS_create_knowledge_entries.exs  # NEW

test/familiar/providers/
├── ollama_adapter_test.exs   # NEW — unit tests with mocked HTTP
├── ollama_embedder_test.exs  # NEW — unit tests with mocked HTTP
├── detector_test.exs         # NEW — detection tests with mocked HTTP
├── providers_test.exs        # NEW — facade delegation tests
├── provider_contract_test.exs # NEW — property-based contract tests
├── ollama_integration_test.exs # NEW — tagged :integration

test/familiar/knowledge/
├── embedding_pipeline_test.exs # NEW — pipeline tests with real sqlite-vec
```

### Previous Story Learnings (from Stories 1.1a, 1.1b)

- sqlite-vec vectors: JSON array strings ONLY, not binary encoding
- `async: false` required for tests touching sqlite-vec virtual tables
- Credo requires alphabetical alias ordering
- `Mox.verify_on_exit!/1` needs context parameter (not zero-arity)
- All stubs must return `{:error, {:not_implemented, %{}}}` (tagged tuple with map, not bare atom)
- Boundary exports must explicitly list self: `exports: [Familiar.Providers]`
- `mix format` auto-fixes long lines — don't fight it
- Credo `strict: true` — no exceptions

### What NOT to Do in This Story

- **Do NOT implement the init scanner** — that's Story 1.4
- **Do NOT create the Anthropic adapter** — architecture lists it but it's not in this story's scope
- **Do NOT implement full Knowledge CRUD** — that's Epic 2 (Story 2.1)
- **Do NOT create the embedding worker pool / Task.Supervisor** — concurrency management comes in Story 1.4
- **Do NOT implement prompt assembly or context window budgeting** — that's Epic 3/5
- **Do NOT add Phoenix Channel streaming** — that's Epic 7

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Provider Interface Decision]
- [Source: _bmad-output/planning-artifacts/architecture.md#Streaming Normalization]
- [Source: _bmad-output/planning-artifacts/architecture.md#Embedding Worker Pool]
- [Source: _bmad-output/planning-artifacts/architecture.md#Data Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Error Handling Convention]
- [Source: _bmad-output/planning-artifacts/architecture.md#Testing Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2]
- [Source: _bmad-output/implementation-artifacts/1-1a-phoenix-project-setup-database-foundation.md#Completion Notes]
- [Source: _bmad-output/implementation-artifacts/1-1b-behaviour-ports-domain-contexts-test-scaffold.md#Completion Notes]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Skipped `ollama ~> 0.9` hex package in favor of raw `Req` — architecture's escape hatch ("Swappable to raw req if library becomes problematic"). The Ollama API is 3 endpoints; the `ollama` package wraps Req anyway, adding indirection without benefit.
- `~s|...|` sigil conflicts with `|` inside JSON strings — switched to `~s(...)` and `~S(...)` sigils
- Credo caught non-alphabetical alias ordering in providers_test.exs and provider_contract_test.exs
- Credo flagged `length(x) > 0` as expensive — changed to `x != []` in integration tests
- `use Familiar.DataCase` and `use Familiar.MockCase` cannot be combined (only one CaseTemplate per module) — pipeline tests use DataCase + manual `import Mox` + `setup :verify_on_exit!`
- sqlite-vec `knowledge_entry_embeddings` virtual table needs manual DELETE cleanup between tests (not sandboxed)
- Stream.resource/3 for streaming: spawns a linked process for Req POST, sends chunks via messages, consumer receives and normalizes. Uses `make_ref()` for message correlation.

### Completion Notes List

- StreamEvent type module with 4 event variants + done_payload + usage types
- OllamaAdapter implements LLM behaviour: chat/2 (non-streaming via Req POST), stream_chat/2 (streaming via Stream.resource with spawned process + NDJSON parsing)
- OllamaEmbedder implements Embedder behaviour: embed/1 via POST /api/embed
- Detector module: detect/0, list_models/0, check_prerequisites/0 with short timeouts
- Providers facade wired: delegates chat/2, stream_chat/2, embed/1 to configured adapters via Application.get_env
- Knowledge.Entry Ecto schema with changeset validation (5 types, 3 sources)
- knowledge_entries migration with 3 indexes + vec0 virtual table (768 dims)
- Embedding pipeline: store_with_embedding/1 and search_similar/2 with real sqlite-vec operations
- Production config: OllamaAdapter + OllamaEmbedder in config.exs, Ollama settings (base_url, models, timeout)
- 62 tests + 4 properties, 0 failures, 9 integration tests excluded by default
- All quality gates pass: compile, format, credo strict

### File List

- lib/familiar/providers/stream_event.ex (new — common stream event types)
- lib/familiar/providers/ollama_adapter.ex (new — Ollama LLM adapter)
- lib/familiar/providers/ollama_embedder.ex (new — Ollama embedder adapter)
- lib/familiar/providers/detector.ex (new — provider auto-detection)
- lib/familiar/providers/providers.ex (modified — facade delegates to adapters)
- lib/familiar/knowledge/entry.ex (new — Ecto schema for knowledge_entries)
- lib/familiar/knowledge/knowledge.ex (modified — store_with_embedding/1, search_similar/2)
- config/config.exs (modified — production adapter config + Ollama settings)
- priv/repo/migrations/20260401200000_create_knowledge_entries.exs (new — knowledge_entries + vec0 table)
- test/test_helper.exs (modified — ExUnit.configure exclude: [:integration])
- test/familiar/providers/ollama_adapter_test.exs (new — 9 unit tests)
- test/familiar/providers/ollama_embedder_test.exs (new — 3 unit tests)
- test/familiar/providers/detector_test.exs (new — 3 integration-tagged tests)
- test/familiar/providers/providers_test.exs (new — 5 unit tests)
- test/familiar/providers/provider_contract_test.exs (new — 4 property tests)
- test/familiar/providers/ollama_integration_test.exs (new — 6 integration tests)
- test/familiar/knowledge/entry_test.exs (new — 9 unit tests)
- test/familiar/knowledge/embedding_pipeline_test.exs (new — 8 unit tests)
