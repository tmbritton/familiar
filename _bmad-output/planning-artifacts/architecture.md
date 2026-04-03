---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'complete'
completedAt: '2026-04-01'
addendum: '2026-04-03'
inputDocuments: [_bmad-output/planning-artifacts/prd.md, _bmad-output/planning-artifacts/prd-brief.md, _bmad-output/planning-artifacts/ux-design-specification.md, _bmad-output/planning-artifacts/prd-validation-report.md, docs/arch-sketch.md]
workflowType: 'architecture'
project_name: 'anthill'
user_name: 'Buddy'
date: '2026-03-29'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
87 FRs across 11 capability areas designed to map 1:1 to implementation epics:
1. Project Initialization & Configuration (FR1–FR7d) — atomic init, convention discovery with evidence, auto-detection
2. Context Store / Knowledge Management (FR8–FR19c) — semantic knowledge store, freshness validation, hygiene loop, backup/restore
3. Planning & Specification (FR20–FR31) — context-aware planning conversation, spec generation with verified assumptions, streaming reasoning trail
4. Task Management (FR32–FR37) — four-level work hierarchy (Epic → Group → Task → Subtask) with state machine and dependency resolution
5. Task Execution (FR38–FR47) — single-agent sequential pipelines, workflow steps (interactive + autonomous), streaming activity, provider override
6. Self-Validation & Reliability (FR48–FR56b) — test/build/lint validation, duplicate detection, atomic rollback, cascading failure handling, provider failure recovery
7. Unified Recovery (FR57–FR57b) — `fam fix` at any hierarchy level with pre-analyzed failure, autonomous self-repair
8. Safety & Security (FR58–FR64) — project directory sandboxing, git protection, secret filtering, vendor skip enforcement
9. Workflow & Role Configuration (FR65–FR69) — markdown-based workflow and role definitions, language config extensibility
10. Web UI / Localhost LiveView (FR71–FR79) — 8 components (spec renderer, triage, search picker, activity feed, knowledge browser, help overlay, status bar, work hierarchy), keyboard-first zero-chrome design
11. Thesis Validation (FR70) — provider comparison, ablation testing, context injection logging

**Non-Functional Requirements:**
24 NFRs across 7 categories driving architectural decisions:
- **Performance:** Context retrieval <2s, inference <5s, init <5min, daemon responsive <1s during execution, web UI <1s load, LiveView <100ms updates, search text <50ms / semantic <200ms
- **Reliability:** Atomic file ops, crash-safe SQLite, interrupted state recovery, auto-backup, 8h+ stability at scale (100+ files, 5K+ lines, 200+ entries)
- **Agent Output Quality:** Linter pass, test generation with behavioral assertions, convention adherence, context window management
- **Integration:** Thin provider interface for Ollama + Anthropic, graceful provider failure handling
- **Output Consistency:** `--json` global flag as interface contract, `--quiet` for scripting, documented schemas
- **Triage Definitions:** Precise four-tier status (✅/🔧/⊘/❌) with clear boundaries
- **Maintainability:** Solo-developer codebase, minimal dependencies, data-driven config (TOML, markdown)

**Scale & Complexity:**
- Primary domain: Elixir/OTP backend + Phoenix LiveView frontend (single BEAM runtime)
- Complexity level: Medium-High
- Architecture should be shaped by MVP tier structure, not all 87 FRs equally:
  - **Tier 1 (Core Loop) drives the minimum viable architecture:** ~5-6 core modules — daemon supervisor, context store, planning engine, agent runner, file manager, work tracker
  - **Tier 2 (Thesis Differentiators) extends core:** init scanner, hygiene loop, self-validation pipeline, dual provider support, self-repair
  - **Tier 3 (UX) adds surface area:** LiveView web UI, notifications, backup/restore UI. Note: `--json` is PRD Tier 3 but promoted to foundational in architecture decisions — implement from day one to force data-first design pattern
- The full 87-FR system implies ~12-15 modules, but the thesis-validation MVP should be buildable with 5-6 core modules that Tier 2 and 3 extend — not 15 equally-weighted components

### Process Architecture Implications

The BEAM process topology is an architectural primitive, not an implementation detail. However, not every concern needs its own process — SQLite and module-level abstractions handle most coordination.

**Core processes (minimal set):**
- **Daemon Supervisor** — top-level Application supervisor. Restarts subsystem supervisors independently
- **Phoenix Endpoint** — serves LiveView web UI and potentially local HTTP API for CLI commands. Crash here must not affect execution
- **Agent Runner** (`DynamicSupervisor` + agent processes) — MVP spawns one agent process at a time. Sequential by policy, not by architecture. Each agent process implements `Familiar.Agent` behaviour, owns its task execution state, publishes activity events via PubSub. On crash: supervisor detects child exit, reads transaction log to determine rollback (incomplete writes) vs resume (completed step, next step pending). Extension path: same `DynamicSupervisor` spawns N agents for parallel execution — concurrency controlled by configuration and dependency resolution in the work tracker
- **Embedding Worker Pool** (`Task.Supervisor` with concurrency limit) — Ollama embedding calls for post-task hygiene (async) and init scan (blocking — init waits for all embeddings to complete). Concurrency capped (configurable, default ~10 concurrent requests) to avoid overwhelming Ollama. Supports batch embedding (multiple texts per request) for init scan efficiency. Progress reporting during init: "Scanning files... Discovering conventions... Building knowledge store (embedding 200/450 entries)...". Init is fully blocking — all embedding completes before init reports success. `Ctrl+C` during init deletes `.familiar/` entirely (atomic per FR7b). No partial embedding state, no degraded search mode
- **Planning Engine Verification Log** — during planning, every verification check (file stat, schema check, convention match, dependency lookup) produces a result record. This single log feeds BOTH the streaming reasoning trail (real-time PubSub events) AND the spec's inline verification marks (✓/⚠ with source citations). Not two parallel systems — one verification log, two consumers. Stored in memory during planning, embedded in spec frontmatter on completion
- **Prompt Assembly Pipeline** — pure function module, not a process. Takes (task, context entries, role definition, conventions, provider config) → assembled prompt. Owns context window budget management: measures token usage of each component, prioritizes most relevant context when approaching limits, warns about truncation. Handles provider-specific prompt formatting (Ollama vs Anthropic message formats). This is where the thesis differentiator lives architecturally — context quality → prompt quality → output quality. Deserves its own module with thorough test coverage

**What does NOT need a dedicated process:**
- **Context store / knowledge queries** — SQLite is single-writer by design. An Ecto Repo with `exqlite` handles concurrency. No GenServer needed to serialize access. The embedding worker pool is orthogonal
- **Work tracker** — same SQLite database, different Ecto context/schema. State machine transitions are SQL updates, not GenServer state
- **File manager** — transaction log pattern in SQLite + a module (not a process). Agent runner calls the module; the module writes to disk and logs to SQLite. Crash-safe via SQLite WAL. Crash recovery (rollback of incomplete transactions) runs as a synchronous function call in `Application.start/2` — before the supervision tree starts. Not a process, but a startup gate
- **Presenter convention** (not a formal layer): don't pass Ecto schemas directly to templates or JSON encoders — derive a map first. This is a code review rule, not an architectural module. With ~4-5 domain objects and ~15 render functions at MVP scale, a formal presenter layer is premature

**Failure isolation principle:** Agent runner crashes are contained — the transaction log in SQLite survives the crash and the daemon rolls back on restart. Database operations (knowledge store, work tracker) go through Ecto/SQLite, which is crash-safe by design. Phoenix endpoint crashes don't affect execution.

**Agent runner tool call loop (core execution):**
1. Send prompt to LLM provider (via behaviour)
2. Receive response (may contain tool calls)
3. If no tool calls → execution complete, return result
4. If tool calls → parse each, execute via tool handler, collect results
5. Append tool call results to message history
6. Send updated messages back to LLM (step 1)
7. Repeat until: no more tool calls, max iterations reached, or error

Tool calls execute sequentially (MVP). Tool handler enforces safety constraints (project directory only, allowed commands only). Each tool call is logged in execution_log for verification and `fam review`. File writes go through the transaction module. This loop is the core of the agent runner — not the supervision or lifecycle, but the actual work.

**Agent runner safety limits (architectural, not prompt-based):**
- **Max tool calls per task:** Configurable limit (default: ~100). Agent runner counts tool invocations and aborts if exceeded. Prevents infinite read/write loops that burn tokens. Prompt instructions alone are insufficient — the runner enforces the budget
- **Task timeout:** Configurable per-task timeout independent of tool call count. Default derived from task complexity estimate. Runner aborts and triggers rollback on timeout
- **Intended files list:** Task decomposition produces a list of files the task is expected to modify. Agent runner warns (does not block) if the agent writes to files outside this list. Warning logged for post-hoc review
- **Full LLM response logging:** Every LLM response is logged in full (not just extracted code). Enables post-hoc review via `fam review #N` and debugging when self-validation passes but output is subtly wrong. Storage: append-only log file in `.familiar/logs/`, rotated per task

### Daemon Lifecycle — Architectural Direction

The daemon is a Phoenix application that runs as a background process per project. The CLI is a thin HTTP client.

**Architecture:**
- Phoenix endpoint serves both LiveView (browser) and JSON API (CLI)
- `fam` CLI commands are HTTP requests to `localhost:PORT/api/*`
- `--json` output contract IS the API response format — one implementation serves CLI, web UI, and scripting
- `--quiet` is a client-side formatting choice on the same API response

**Per-project daemon scoping:**
- Each project directory gets its own daemon (own BEAM instance, own port)
- Dynamic port stored in `.familiar/daemon.json` after startup
- `fam` reads `.familiar/daemon.json` to find the running daemon's port
- Multiple projects can run daemons simultaneously on different ports

**Lifecycle:**
- **Auto-start:** `fam` checks `.familiar/daemon.json` for a running daemon (HTTP health check to stored port). If not running or not responding → start daemon as background process → write port to `daemon.json` → wait for health check → execute command
- **PID file:** `.familiar/daemon.pid` for process management. Advisory file lock during startup prevents two `fam` commands from racing to start two daemons
- **Shutdown:** `fam daemon stop` sends shutdown signal. Also stops on system shutdown. Daemon writes clean shutdown marker — absence of marker on next start indicates crash recovery needed
- **Crash recovery:** On startup: (1) Check database integrity → auto-restore from backup if corrupted. (2) Check for incomplete file transactions in SQLite → rollback. (3) **Orphaned task reconciliation:** for every task in `in-progress` or `validating` state, verify transaction log entries exist. If none found (WAL lost them) → mark as `failed: interrupted — no recovery data`. This handles the edge case where the OS kills the BEAM without clean shutdown (laptop sleep, power loss, OOM kill)

**Version handshake:**
- Health endpoint returns daemon version: `GET /api/health → {status: "ok", version: "0.3.1"}`
- CLI checks version compatibility on every command. Major version mismatch → "Daemon is running version 0.2.0 but CLI is 0.3.1. Run `fam daemon restart` to update."
- Semantic versioning on the HTTP API: major version bump = breaking changes

**CLI entry point flow (`Familiar.CLI.Main`):**
1. Parse arguments
2. Check if `.familiar/` exists in current directory
3. **If no `.familiar/` (first run):**
   - Run prerequisite checks (Ollama running, models available)
   - Start minimal supervision tree: Repo, provider adapter, embedding worker (no Phoenix endpoint)
   - Run init scanner in-process: scan → classify → extract knowledge → embed → store
   - On completion: start daemon as background process
   - Report init results and exit
4. **If `.familiar/` exists (normal operation):**
   - Read `.familiar/daemon.json` for daemon port
   - Health check → start daemon if not running
   - Dispatch command via HTTP (simple) or Channel (interactive)
5. **Daemon unresponsive fallback:** If HTTP is unresponsive after timeout, CLI reads `.familiar/daemon.pid` and sends `SIGTERM`. Two shutdown paths: HTTP (graceful) → PID signal (forceful)

**Why HTTP API over distributed Erlang:**
- Phoenix endpoint already exists for LiveView — zero additional infrastructure
- No epmd daemon, no cookie files, no distributed Erlang security surface
- Works from any scripting language (curl, Python, etc.) — aligns with `--json` as platform API
- Simpler mental model for a solo-dev codebase
- Auto-start health check is a simple HTTP GET, not Erlang node discovery

### Graceful Degradation Modes

The architecture must support three operational modes, not just "working" and "broken":

**Full mode:** Ollama running, sqlite-vec loaded, all features available. Normal operation.

**Degraded mode (no Ollama):** Daemon starts and serves web UI. Read-only commands work: `fam status`, `fam tasks`, `fam search` (text-only, no semantic), `fam review`, `fam log`. Write commands that need LLM (plan, do, fix) fail with clear message: "Ollama unavailable — start Ollama to plan and execute tasks. Read-only commands still work." Global status indicator in web UI shows degraded state. This matters because: the user reboots, forgets to start Ollama, types `fam status` to check overnight results — that must work.

**Recovery mode:** Database integrity check on startup fails. Auto-restore from backup (FR19c). If no backup: `fam init --rescan` rebuilds from filesystem. Daemon enters recovery automatically — user sees global status: "Database restored from backup (2026-03-28). Verify with `fam status`." Recovery is a startup path, not a runtime mode.

**sqlite-vec:** Required dependency, bundled with the release. If it fails to load, the daemon logs the error and exits — this is a build/installation problem, not a runtime degradation. Fix the build, don't build a fallback.

### Data Flow & State Boundaries

**Single database, separate Ecto contexts:**

The PRD's "context store" and "work tracker" are different tables in the same SQLite database, not different systems. One Ecto Repo, different contexts:
- **Knowledge context:** conventions, decisions, gotchas, relationships. Write-rarely (post-task, init), read-often (every dispatch), semantic queries via sqlite-vec
- **Work context:** task hierarchy, status, dependencies, file modification tracking. Write-often (every status transition), read-often (every status check), structured queries by ID/status
- **File transaction log:** intended writes, completion status, rollback records. Write-per-file-op, read on crash recovery

The real architectural boundary is **query path** (synchronous SQL, must be <2s) vs **embedding path** (async Ollama calls via worker pool, can take seconds). Not knowledge vs operational.

**Critical data flow path (planning → execution):**

```
User intent (CLI)
  → Planning engine (context queries + LLM conversation)
    → Spec (markdown file in project directory)
      → User review (browser or $EDITOR)
        → Task decomposition (spec → hierarchy in work tracker)
          → Execution (per-task: context injection → LLM → tool calls → file writes via transaction log)
            → Validation (test/build/lint/coverage/duplicate check)
              → Knowledge capture (post-task hygiene → async embedding → knowledge store)
```

**Spec approval stat check:** When the user approves a spec (browser `a` keybinding or CLI), the system stats the spec file and compares mtime/content hash to what was rendered. If the file was modified externally (e.g., user edited in `$EDITOR` while browser was open) → reload, show diff, re-render before allowing approval. Same pre-action stat check pattern as the file transaction module. Prevents task decomposition from a stale spec.

**Freshness validation as synchronous gate:** Every task dispatch triggers freshness checks — stat referenced files, exclude deleted, auto-refresh modified. On the critical execution path (not background). Batch file stats, parallelize where possible, fail-open with warnings rather than blocking indefinitely. Must complete within the <2s retrieval budget.

**Planning conversation persistence — resolved:**
Option (b): persist message history in SQLite. Table: `planning_messages` (session_id, role, content, tool_calls, timestamp). Resume replays history into LLM context. Cost: one migration, one Ecto schema, ~50 lines in planning engine. Benefit: resume never re-asks questions the system already explored. The user's core expectation is "the system remembers what we discussed" — stateless resume would violate this by losing conversation nuance. The spec is still the durable checkpoint for WHAT was decided, but the conversation history preserves HOW it was explored.

**Prompt assembly as the thesis-critical transformation:**
The most architecturally significant data transformation is: context + task + role + conventions → LLM prompt. This is where:
- Context window budget is managed (measure each component's token cost, prioritize, truncate)
- Provider differences are abstracted (Ollama chat format vs Anthropic Messages API)
- The thesis is tested (context quality → prompt quality → output quality)
- Ablation testing hooks in (disable context injection, compare results)
- **Ablation comparison is post-hoc, not automated.** The architecture logs everything needed (injected context, provider, execution details, validation results). Comparison is analysis during the 50-task baseline phase — user reviews outputs via `fam review` and rates acceptance. Automated comparison scoring is a post-MVP enhancement if the thesis validates

Prompt assembly is a pure function: returns `{prompt, %{truncated: boolean, dropped_entries: list, token_budget: map}}`. The caller (agent runner) reads metadata and handles side effects — updating triage with `context-truncated` sub-state, logging dropped entries for `fam review`. Prompt assembly itself has no side effects. Independently testable: given these inputs, assert the prompt contains X, fits within Y tokens, formats correctly for provider Z, and metadata accurately reports truncation.

**Requirement coverage validation (part of self-validation pipeline):**
After code generation, the validation pipeline checks that each element of the task description was addressed:
- Task decomposer extracts acceptance checks from the task description (structured list of "this task should: [x, y, z]")
- Validation pipeline verifies each check: file exists, function defined, test covers behavior
- For semantic checks that can't be verified structurally: flag as "manual review recommended" in triage
- This is a checklist approach, not an LLM re-review — keeps validation deterministic and fast

**Verification derived from tool call log:**
Verification = "did a tool call support this claim?" The planning engine logs all tool calls (file reads, context queries) during spec generation. Spec claims that cite files present in the tool call log are marked ✓ verified. Claims citing files NOT in the tool call log are marked ⚠ unverified. No separate claim parser or verification module — the tool call log IS the verification source. The verification result log is the tool call log annotated with claim references. This is the architectural defense against hallucinated verification marks: the LLM cannot self-report verification status, only actual file reads count.

**Question repetition prevention:**
The planning engine's primary defense against repeat questions is context retrieval (FR21). If the answer exists in the knowledge store, the system uses it instead of asking. No separate embedding-based deduplication system — good context retrieval IS question deduplication. The repeat-question metric (PRD success criteria) is tracked via user-flagged repetitions during baseline measurement, not via an architectural deduplication module.

**Knowledge capture rules for retry scenarios:**
Post-task hygiene runs after task completion (success or successful retry). Critical distinction:
- **Domain knowledge** (conventions applied, decisions made, relationships discovered): capture from the SUCCESSFUL execution only. Failed attempt's observations may reflect bad code and would poison the knowledge store
- **Failure gotchas** (edge cases, ambiguities, patterns that confused the agent): capture from the FAILURE REASON, not the failed code. "Session middleware has two conflicting patterns — cookie-based for web, token-based for API" is a valuable gotcha. The wrong middleware code the agent wrote is not
- Implementation: post-task hygiene receives both the final (successful) execution context AND the failure log if retries occurred. Two extraction passes, different source material

**Convention injection — MVP strategy:**
MVP uses semantic retrieval only for conventions (same path as all other context). During the 50-task baseline phase, track "convention should have been applied but wasn't" as a quality signal. If convention miss rate exceeds threshold (calibrated from baseline), upgrade to two-source injection: mandatory conventions tagged with file patterns + semantic context.

This avoids premature complexity (tagging conventions with file patterns, two injection paths) while providing a measured upgrade trigger. The init scanner still captures conventions with evidence — but pattern metadata tagging is deferred until needed.

**Upgrade path (if semantic retrieval proves insufficient):**
- Tag conventions with applicable file patterns (e.g., "handler naming" → `handler/*.go`)
- Prompt assembly checks which files the task will likely touch, injects matching conventions regardless of semantic similarity
- Two injection sources: mandatory conventions by file pattern + semantic context by query
- Decision triggered by data from baseline measurement, not upfront assumption

**File transaction module — architectural constraints:**
- **Strict write sequence:** (1) Log write intent to SQLite (file path, content hash, task ID) → (2) Write file to disk → (3) Log completion to SQLite. Crash between 1-2: rollback finds intent without file, nothing to clean. Crash between 2-3: rollback finds intent without completion, deletes written file
- **Pre-write stat check timing:** Immediately before step 2, not at task start. If file modified since task start → skip write, save as `.fam-pending`, log conflict. Agent receives "file changed" signal and must handle gracefully (not crash)
- **Idempotent rollback:** Each file's rollback has its own status (pending/rolled-back/skipped). Re-running rollback after partial completion finishes remaining files without double-reverting
- **Conflict visibility:** `fam status` reports pending `.fam-pending` files in its output. Web UI triage shows conflict count

**Triage sub-states (annotations, not additional tiers):**
The four-tier triage model (✅/🔧/⊘/❌) is the primary classification. Sub-states are annotations shown in detail views:
- 🔧 `context-truncated`: task completed but context window was truncated. Invites review, not a failure
- ⊘ `conflict-pending`: task write deferred to `.fam-pending` due to concurrent edit. Blocked on user resolution
Sub-states appear in `fam review` and detail views. Top-level triage shows only the four primary states

### Technical Constraints & Dependencies

- **Solo developer** — both a resource constraint and a design principle. Architecture must be understandable and modifiable by one person
- **Target hardware:** Apple M1/M2 Pro, 16-32GB unified memory. Local model: 14B parameter class
- **Technology stack (PRD-defined):** Elixir/OTP, Phoenix LiveView, SQLite + sqlite-vec, Ollama, Anthropic API
- **No external services for core functionality** — fully functional offline with local Ollama
- **AGPL-3.0 license** — all dependencies must be license-compatible
- **Sequential execution only** (MVP) — single agent at a time by policy. Architecture uses `DynamicSupervisor` that supports N children — concurrency unlocked by configuration change, not rewrite
- **No client-daemon protocol** (MVP) — CLI is a thin HTTP client to the Phoenix endpoint. No TCP/RESP, no distributed Erlang

### Extensibility Architecture

**Design principle:** Build for one, design the seams for many. MVP implements single-agent sequential coding. The architecture must not preclude multi-agent parallel execution or domain-agnostic use.

**Behaviour boundaries (extension seams):**

| Boundary | Behaviour | MVP Implementation | Future Extension |
|---|---|---|---|
| Agent execution | `Familiar.Agent` | Single coding agent (analyst/coder/reviewer roles via role files) | Multiple concurrent agents, domain-specific agents |
| Tool access | `Familiar.Tool` + registry | 7 tools: read_file, write_file, delete_file, run_command, search_context, store_context, list_files | MCP client pool, domain-specific tools (web search, API calls) |
| Validation | `Familiar.Validator` | TestRunner, BuildChecker, LintChecker, RequirementCoverage, DuplicateDetector | Domain validators (brand voice, fact-check, compliance) |
| Knowledge capture | `Familiar.Extractor` | Code-focused: conventions, decisions, relationships, gotchas | Domain extractors (brand patterns, audience insights, research claims) |
| Prompt assembly | `Familiar.PromptStrategy` | Coding-optimized context assembly | Domain-specific prompt strategies, multi-model routing |
| Workflow execution | `Familiar.WorkflowExecutor` | Sequential step execution | Parallel step execution, agent coordination, DAG-based workflows |

**Implementation approach:**
- Do NOT pre-build behaviours. Build the MVP coding implementation first as concrete modules (e.g., `Familiar.CodingAgent`, not `Familiar.Agent` behaviour + implementation)
- Extract behaviours from working code when a second implementation is needed or when the API boundary is clearly stable
- Each behaviour gets a contract test module — any new implementation must pass the same contract
- Behaviours emerge from the first implementation, not from upfront design
- **Note:** The behaviour table above is the anticipated extensibility map, not a build instruction. It guides WHERE to expect seams, not WHEN to build them
- **Distinction:** These 6 extensibility behaviours (anticipated, extracted from working code later) are SEPARATE from the 6 testing ports defined in Testing Architecture (built from day one as external system boundaries). Extensibility behaviours emerge from domain logic. Testing ports mock external systems. Different purpose, different timing

**Contract testing for behaviours:**
Each behaviour defines a contract test module (e.g., `Familiar.AgentContractTest`) that exercises the behaviour callbacks with known inputs and expected output shapes. Any module implementing the behaviour must pass the contract. MVP: one implementation per behaviour, one contract test. Extension: new implementations get the contract for free — they pass or they don't ship.

**Agent runner extensibility:**
- MVP: `DynamicSupervisor` starts one agent process at a time. Sequential by policy, not by architecture
- Extension: same `DynamicSupervisor` starts N agents. Concurrency controlled by configuration and dependency resolution in the work tracker
- The work tracker's "ready" state check queries dependencies in the database (`all dependencies complete?`), not `last task completed?`. Correct for sequential, ready for concurrent

**Workflow extensibility:**
- MVP: markdown workflow files define sequential agent pipelines. Steps execute one at a time
- Parsed but ignored for MVP: `parallel: true` flag on workflow steps
- Extension: workflow executor reads parallel flag, spawns concurrent agents for independent steps

**Context store extensibility:**
- SQLite WAL mode handles concurrent reads (multiple agents querying context simultaneously)
- Embedding worker pool needs backpressure queue (not unbounded Task.Supervisor) for when multiple agents trigger post-task hygiene simultaneously
- Global context store (cross-project knowledge) is a second SQLite database with the same Ecto context — not a different architecture

**Domain-agnostic principle:**
- The orchestration layer (daemon, runner, tracker, workflows) knows nothing about coding
- Domain knowledge lives in: role files (markdown), validation modules (behaviours), extraction modules (behaviours), language config (TOML)
- Switching domains = different directory of role/workflow/config files, different validator/extractor implementations
- The context store schema is already domain-agnostic (facts, decisions, gotchas, relationships work for any domain)

### Cross-Cutting Concerns Identified

**Foundational (design before implementation):**
1. **Daemon lifecycle & CLI-daemon communication** — HTTP API on local Phoenix endpoint. Per-project daemon with dynamic port. Auto-start on first `fam` command. Shapes every CLI command's implementation (thin HTTP client)
2. **Context freshness** — every task dispatch validates referenced entries against filesystem. Synchronous gate on the critical execution path. Affects: knowledge context, planning, execution, recovery
3. **Atomic file operations via transaction log** — write/rollback lifecycle tracked in SQLite with strict ordering (log intent → write → log completion). Spans: execution, cancellation, failure recovery, concurrent edit detection (`.fam-pending`). Module-level abstraction, not a process
4. **Provider abstraction** — Ollama and Anthropic behind a common behaviour. Affects: planning, execution, thesis validation, configuration
5. **Extensibility seams (behaviour boundaries)** — component boundaries should allow future extraction of Elixir behaviours. MVP builds concrete modules. Behaviours extracted when a second implementation is needed. Foundational because closing an extension seam early is expensive to reopen

**Incremental (implement as features are built):**
6. **Error triage model** — four-tier status (✅/🔧/⊘/❌) with roll-up across hierarchy levels. Affects: work tracker, CLI output, web UI, notifications
7. **`--json` output contract** — implement on the FIRST command built, not deferred. Every command separates data (struct/map from context) → presentation (presenter transforms to output shape) → formatting (JSON or pretty text). If `--json` works, the data layer is clean. Forces data-first design from day one
8. **Streaming output** — reasoning trail during planning, activity feed during execution. PubSub-driven: agent runner and planning engine publish events, CLI and LiveView subscribe
9. **Safety sandboxing** — project directory restriction, git protection, deletion constraints, secret filtering. Enforced across: agent runner, file transaction module, knowledge context

**Moved to appropriate sections (not cross-cutting at MVP scale):**
- Knowledge-not-code rule → knowledge context ingestion documentation
- Thesis validation / ablation mode → dedicated architecture section when addressed (hooks in prompt assembly + agent runner + work tracker)
- Verification result pipeline → planning engine design (tool call log feeds both trail and spec marks)
- Presenter convention → coding conventions (derive maps from schemas before rendering)

## Starter Template Evaluation

### Primary Technology Domain

Elixir/OTP + Phoenix LiveView — defined by PRD. Single BEAM runtime serving both the daemon (background task execution, HTTP API) and web UI (LiveView). No framework selection needed.

### Starter Options Considered

**Only viable option: `mix phx.new` (Phoenix project generator)**

Phoenix has one canonical project generator. The decision is flag selection, not starter selection. Alternative approaches (bare Mix project without Phoenix, or Plug without Phoenix) would require rebuilding LiveView integration, PubSub, and endpoint configuration — significant work for zero benefit.

### Selected Starter: `mix phx.new` with SQLite and minimal flags

**Rationale:** Phoenix 1.8 generates a project with LiveView, Ecto, and PubSub already configured — exactly the infrastructure Familiar needs. SQLite support is first-class via `--database sqlite3`. Stripping unused features (Tailwind, mailer, dashboard) is less work than adding missing ones to a bare project.

**Initialization Command:**

```bash
mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard
```

**Current Versions (verified March 2026):**

| Dependency | Version | Purpose |
|---|---|---|
| Phoenix | 1.8.5 | Web framework, endpoint, PubSub |
| Phoenix LiveView | 1.1.28 | Real-time web UI (spec review, triage, search) |
| Ecto + ecto_sqlite3 | latest | Database access, SQLite adapter |
| exqlite | 0.35.0 | SQLite3 NIF driver |
| sqlite_vec | 0.1.0 | sqlite-vec extension wrapper for Ecto (Float32 vectors) |

**Architectural Decisions Provided by Starter:**

**Language & Runtime:**
Elixir with standard Mix project structure. ExUnit for testing. Releases via `mix release`.

**Web Layer:**
Phoenix Endpoint with LiveView socket, PubSub configured. HTTP routing via Phoenix Router. JSON encoding via Jason.

**Database:**
Ecto Repo with SQLite3 adapter. Migrations via `mix ecto.migrate`. Database path in config (not URL).

**Real-time:**
Phoenix PubSub (pg2 adapter for single-node) for event broadcasting. LiveView for server-push updates to browser.

**Styling (to be replaced):**
Generates with Tailwind CSS — will be stripped and replaced with custom minimal CSS per UX spec. No CSS framework, no component library.

**Post-Generation Modifications:**

1. Strip Tailwind CSS configuration and dependencies — replace with custom CSS tokens
2. Strip default Phoenix layout (navbar, sidebar) — zero-chrome per UX spec
3. Add `sqlite_vec` dependency and configure extension loading in Repo
4. Add `req` dependency for CLI HTTP client
5. Configure project for daemon architecture (background supervision tree, API routes, health endpoint)
6. Add CLI entry point module (the `fam` command as an escript or release command)
7. Replace license with AGPL-3.0
8. Configure `.familiar/` project directory structure

**Note:** Project initialization using this command should be the first implementation story.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
1. CLI-daemon communication: Hybrid HTTP + Phoenix Channel
2. Project structure: Domain-driven Ecto contexts
3. Provider interface: Hex libraries behind provider behaviour

**Important Decisions (Shape Architecture):**
4. Schema design: Context-owned tables, auto-migrate on startup
5. Testing: Hexagonal architecture with Mox-based DI, 6 behaviour ports
6. Config: TOML + YAML frontmatter, PRD-aligned directory structure

**Deferred Decisions (Post-MVP):**
- Release packaging details (escript vs release command for `fam` CLI)
- Structured logging format and `fam log` storage optimization
- Telemetry events and metrics collection

### CLI-Daemon Communication

- **Decision:** Hybrid — HTTP for simple commands, Phoenix Channel for interactive
- **Simple commands** (`status`, `tasks`, `search`, `review`, `log`, `config`, `backup`, `restore`, `daemon`): HTTP request-response via `req`
- **Interactive commands** (`plan`, `fix`): Phoenix Channel (WebSocket) for bidirectional streaming — reasoning trail, clarifying questions, user responses, spec delivery over one connection
- **`fam do`**: Dispatch via HTTP POST. Progress via `fam watch` (Channel) or `fam status` (HTTP poll)
- **`fam do --all` completion notification:** After HTTP dispatch, the CLI can optionally subscribe to Channel topic `familiar:execution:{epic_id}` for completion/failure events (this is what `fam watch` does). If the CLI exits before completion, the daemon continues — OS notification fires on completion, `fam status` shows results on next poll
- **WebSocket client:** `slipstream` or `fresh` (Phoenix Channel clients for Elixir). Verify maintenance status before selecting
- **Channel handlers and API controllers both call context public APIs** — same data source, different transport
- **Rationale:** Simple commands stay simple. Interactive commands get the streaming UX they need
- **Affects:** CLI client module (needs both `req` and a WebSocket client), Phoenix router (API routes + Channel), planning engine, fix conversation engine

**Agent process type (MVP):** Agent execution is supervised. MVP runs one agent at a time. Crash triggers rollback via transaction log. Extension: supervisor spawns N agents for parallel execution.

### Project Structure

- **Decision:** Domain-driven contexts mapping to capability areas

```
lib/familiar/
  knowledge/        # Context store, embeddings, freshness, hygiene
  work/             # Task hierarchy, state machine, dependencies
  planning/         # Planning engine, spec generation, verification
  execution/        # Agent runner, tool calls, validation pipeline
  files/            # File transactions, rollback, conflict detection
  providers/        # Ollama, Anthropic, provider behaviour
  cli/              # CLI entry point, HTTP client, Channel client
lib/familiar_web/
  api/              # JSON API controllers
  live/             # LiveView modules
  channels/         # CLI interactive channel
```

- **Rationale:** Maps to 11 capability areas / implementation epics. Clear module boundaries. Each context owns its Ecto schemas
- **Affects:** All module organization, test structure mirrors lib

**Context boundary enforcement:**
Each context exposes a top-level public API module (e.g., `Familiar.Knowledge`, `Familiar.Work`, `Familiar.Planning`). All inter-context communication goes through these public modules. Rule: never alias a module from inside another context. If `Execution` needs knowledge entries, it calls `Familiar.Knowledge.search(query)`, never `Familiar.Knowledge.Store.query(embedding)`. This makes the dependency graph explicit, testable, and visible in the public module's function list.

**CLI as client, not domain:**
`lib/familiar/cli/` is architecturally a CLIENT of the daemon, not a business domain context. It calls HTTP endpoints and Channel topics only — never imports from `knowledge/`, `work/`, `planning/`, or any other context directly. Same boundary as if the CLI were a separate application. Candidate for extraction into a separate Mix project post-MVP.

### Provider Interface

- **Decision:** Existing hex libraries behind provider behaviour
- **Libraries:** `ollama` ~> 0.9 (Ollama), `anthropix` ~> 0.6 (Anthropic)
- **Pattern:** Both implement `Familiar.Providers.LLM` behaviour. Swappable to raw `req` if library becomes problematic
- **Rationale:** Libraries already implement streaming, tool use, structured outputs. Behaviour boundary provides escape hatch
- **Affects:** `lib/familiar/providers/`, prompt assembly, agent runner

**Streaming normalization:**
Provider adapters translate provider-specific stream events into a common format:
- `{:text_delta, binary()}` — incremental text content
- `{:tool_call_delta, map()}` — incremental tool call construction
- `{:tool_result, map()}` — completed tool call result
- `{:done, %{content: binary(), tool_calls: list(), usage: map()}}` — stream complete

The adapter owns this translation. Consumers (planning engine, agent runner, Phoenix Channel) work with the common format only. This is the adapter's primary complexity.

### Data Architecture

- **Decision:** Single SQLite database, schema ownership per context

| Context | Tables | Access Pattern |
|---|---|---|
| `knowledge/` | knowledge_entries (text, embedding, type, source, metadata) | Write-rarely, read-often, semantic queries |
| `work/` | epics, groups, tasks, subtasks, file_modifications | Write-often, read-often, structured queries |
| `files/` | file_transactions (intent, path, hash, status, task_id) | Write-per-file-op, read on crash recovery |
| `execution/` | execution_logs (task_id, tool_calls, llm_responses) | Append-only, read for review |
| `planning/` | specs (frontmatter index), planning_messages (session_id, role, content, tool_calls, timestamp) | Write during planning conversation, read on resume and review |

- **Migration strategy:** Standard Ecto migrations. Auto-migrate on daemon startup. Init creates database and runs all migrations

**Init scan architecture:**
Init is fully blocking — scanning, convention discovery, knowledge extraction, AND embedding all complete before init reports success. No partial state, no degraded search mode.

- Progress reporting during init: "Scanning files... Discovering conventions... Building knowledge store (embedding 200/450 entries)..."
- Init is atomic per FR7b: `Ctrl+C` at any point deletes `.familiar/` entirely
- Large projects take longer (embedding is the bottleneck, ~200ms per entry via Ollama). Progress reporting makes the wait acceptable
- This eliminates: FTS5 fallback, "text-only" search, embedding completion tracking in `fam status`, partial embedding state

**Init scan time budget:**
Target: init completes within 5 minutes for projects up to 200 source files (PRD NFR). Design strategies:
- Parallelize file reading (batch file system reads)
- Batch LLM extraction calls (multiple files per prompt where possible)
- Prioritize: extract conventions and architecture patterns first (high-value), file summaries second (volume)
- If project exceeds 500 files: init extracts top-200 by significance (source files over config/generated), defers remainder to background processing after init completes
- Progress bar with estimated time makes any wait acceptable

**Init scanner defaults (before config exists):**
Built-in skip patterns: `.git/`, `vendor/`, `node_modules/`, `_build/`, `deps/`, `.elixir_ls/`, `*.beam`, `*.pyc`, `go.sum`, `mix.lock`, `package-lock.json`, `yarn.lock`. User overrides in `.familiar/config.toml` after init completes.

**Knowledge entry content strategy (knowledge-not-code):**
The init scanner extracts natural language knowledge about the code, not code copies. Entries embed well because they're prose descriptions, not syntax.

Entry types stored during init scan:
- **File summaries:** Purpose, role, dependencies, patterns used — one entry per significant file
- **Conventions:** Naming patterns, directory structure, error handling, template patterns — with evidence counts
- **Architecture patterns:** Repository pattern, handler structure, test organization — structural observations
- **Relationships:** File dependencies, module coupling, template-to-handler mapping
- **Decisions:** Discovered conventions that represent implicit decisions (e.g., "all errors wrapped with fmt.Errorf")

NOT stored: raw code, function signatures, comments, file contents. Code is ALWAYS read fresh from the filesystem at execution time. The knowledge store tells the agent WHERE to look and WHAT to expect — it's an index card system, not a code mirror.

Post-task hygiene adds new entries in the same format: decisions made, gotchas discovered, relationships found. Never code produced.

**Secret detection (structural, not heuristic per PRD):**
Before storing any knowledge entry, scan text for common secret patterns:
- Regex: API key formats (sk_live_*, AKIA*, ghp_*, etc.), base64-encoded tokens >40 chars, URLs with embedded credentials
- Environment variable names: DATABASE_URL, SECRET_KEY, API_KEY, etc.
- If detected: strip the secret value, store the REFERENCE ("Stripe API key configured in .env") not the VALUE
- Simple regex list, not ML-based detection. Matches PRD philosophy: "structural mitigations, no heuristic detection"

**sqlite-vec integration risk:** Vector columns in SQLite via `sqlite_vec` custom Ecto types are non-standard. Early spike needed to verify: embedding insert, similarity query syntax, index performance at target scale (200+ entries). De-risks the thesis-critical context retrieval path.

### Testing Architecture

- **Decision:** Hexagonal architecture with Mox-based dependency injection
- **Pattern:** External system boundaries accessed through behaviours (ports). Mox mocks in unit tests, Ecto sandbox for database tests, real adapters in integration tests
- **Coverage target:** Mid-high 90s% global threshold in CI. 100% enforced on critical path modules

**6 behaviour ports (external system boundaries):**

| Port (Behaviour) | Production Adapter | Test Mock |
|---|---|---|
| `Familiar.Providers.LLM` | OllamaAdapter, AnthropicAdapter | Mox mock (scripted responses) |
| `Familiar.Files.FileSystem` | LocalFileSystem | Mox mock (in-memory) |
| `Familiar.Knowledge.Embedder` | OllamaEmbedder | Mox mock (deterministic vectors) |
| `Familiar.System.Shell` | RealShell | Mox mock (scripted results) |
| `Familiar.System.Notifications` | TerminalNotifier, NotifySend | Mox mock (collecting) |
| `Familiar.System.Clock` | SystemClock | Mox mock (frozen/controllable time) |

**Database-touching modules — Ecto sandbox (no behaviour needed):**
Knowledge store, work tracker, file transaction log, execution logs, planning sessions. Tested against real SQLite in isolated per-test transactions. Catches SQL bugs that mocks would hide. One test suite covers both logic and database interaction.

**Pure logic modules — direct unit tests (no mocks needed):**
Task state machine, dependency resolver, triage roll-up, prompt assembly. Pure functions, tested with inputs and assertions.

**100% coverage enforced on critical modules:**

| Module | Why 100% |
|---|---|
| `Work.TaskStateMachine` | State machine bugs corrupt entire work hierarchy |
| `Files.TransactionLog` | Rollback bugs mean data loss |
| `Planning.PromptAssembly` | Prompt bugs silently degrade every task's output |
| `Planning.Verification` | Verification bugs mean false ✓ marks → false trust |
| `Execution.ValidationPipeline` | Validation bugs let bad code through |
| `Work.DependencyResolver` | Dependency bugs execute tasks out of order |

**Property-based testing with StreamData:**
For the 6 critical modules, add property-based tests alongside example-based tests. StreamData generates thousands of random cases to find edge cases that neither humans nor AI agents would think to write. Dependency: `{:stream_data, "~> 1.0", only: :test}`.

| Module | Property |
|---|---|
| `Work.TaskStateMachine` | No sequence of valid transitions reaches an illegal state |
| `Work.DependencyResolver` | Resolution never produces dependency cycles; all ready tasks have satisfied dependencies |
| `Planning.PromptAssembly` | Output never exceeds token budget; truncation metadata is accurate |
| `Planning.Verification` | Every ✓ mark has a corresponding tool call in the log; no tool call log entry is missed |
| `Files.TransactionLog` | Rollback after any crash point leaves filesystem in a consistent state |
| `Execution.ValidationPipeline` | Pipeline runs all applicable validators; never silently skips one |

**Property-based contract tests:**
Behaviour contract tests use StreamData to verify: "for ANY valid input, the adapter returns a valid result or error and NEVER crashes." Stronger than example-based contracts.

**Property test seed strategy:**
- CI: fixed seeds for deterministic reproduction. Failing seed captured in output
- Local development: random seeds for exploratory testing
- New edge cases become example-based regression tests + added to CI seed list
- Never skip a flaky property test — intermittent failure IS the bug report

**Test tagging:** Default `mix test` runs unit + sandbox tests (fast, deterministic, CI-safe). `--include integration` adds real Ollama/Anthropic tests. `--include slow` adds endurance tests.

- **Rationale:** Extensive testability is the primary guardrail for AI-agent-built code. Hexagonal ports at real external boundaries, Ecto sandbox for database logic, pure function tests for business rules. Mid-high 90s coverage without extreme gymnastics.

### Error Handling Convention

Context public API functions return `{:ok, result}` or `{:error, {type, details}}` using tagged tuples:
- `{:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}`
- `{:error, {:validation_failed, %{step: :lint, output: "..."}}}`
- `{:error, {:file_conflict, %{path: "handler/auth.go", task_id: 42}}}`

Recoverability is a policy function, not a data attribute:

```elixir
def recoverable?({:provider_unavailable, _}), do: true
def recoverable?({:file_conflict, _}), do: false
def recoverable?({:validation_failed, _}), do: true  # retry once
```

The `recoverable?/1` function drives the self-repair decision: `true` → retry/auto-repair, `false` → escalate to user as ❌. Structured errors render cleanly in triage display, `--json` output, and web UI.

### Config Management

- **Decision:** TOML for project config, YAML frontmatter for role/workflow markdown
- **Libraries:** `toml` (bitwalker) for TOML parsing, `yaml_elixir` for frontmatter
- **Config validation:** Invalid config → `{:error, {:invalid_config, %{field: ..., reason: ...}}}` with specific field and reason. Malformed role/workflow → clear error per FR67
- **Directory structure:**

```
.familiar/
  config.toml          # Provider settings, language config, scan preferences
  daemon.json          # Runtime: port, PID (not user-edited)
  daemon.pid           # Runtime: process ID
  familiar.db          # SQLite database
  backups/             # Auto-backup snapshots
  logs/                # Per-task LLM response logs
  roles/               # Agent role markdown files
  workflows/           # Workflow definition markdown files
```

### Foundational Implementation

The architectural decisions require upfront infrastructure before feature stories:

**Test scaffold:**
- 6 Mox mock definitions (one per behaviour port)
- StreamData generators for critical module property tests
- Test factories for knowledge entries, tasks, specs
- ExUnit case templates for common test setups (sandbox, mocks)

**Context boundaries:**
- 7 public API facade modules with documented function signatures
- Context boundary enforcement via compile-time checks (consider `boundary` hex package)

**Daemon lifecycle:**
- Auto-start, health endpoint, PID file, crash recovery sequence
- Phoenix endpoint configured for both LiveView and JSON API

**Config loading:**
- TOML parser + validation
- Markdown frontmatter loader + validation

**sqlite-vec integration spike:**
- Proof-of-concept for vector columns in Ecto using `sqlite_vec` custom types
- Verify: insert embeddings, query by vector similarity, index performance at 200+ entries
- De-risks the thesis-critical context retrieval path — do it early

**Knowledge extraction spike:**
- Proof-of-concept for init scanner knowledge extraction: given a source file, produce natural language entries (file summary, conventions, patterns, relationships)
- Test embedding quality: do the extracted descriptions retrieve well for task-relevant queries?
- Establish the LLM prompt for knowledge extraction (the init scanner uses the LLM to summarize files, not just regex)
- This spike validates that the "index card system" approach produces entries that embed and retrieve meaningfully

This infrastructure is built alongside the first feature stories, not as a separate phase. Each epic's first story includes the scaffolding it needs.

### Decision Impact Analysis

**Implementation Sequence:**
1. Phoenix project init with SQLite (starter)
2. Domain-driven context structure + Ecto schemas + migrations
3. Hexagonal port/behaviour definitions (6 ports)
4. Provider adapters (Ollama first, Anthropic second)
5. HTTP API routes + Phoenix Channel
6. CLI client (HTTP + WebSocket)
7. Core business logic behind ports (knowledge, work, planning, execution, files)
8. LiveView components
9. Test infrastructure (mocks, factories, contract tests, property tests)

Note: items 2-3 and 7-9 are parallel-capable. Port definitions (3) should be established early because they shape everything downstream.

**First feature story prerequisite chain:**
Init scan (the first deliverable feature) requires all of these working:
- Ecto Repo + SQLite + sqlite-vec (schema, migrations, vector columns)
- Provider adapter (Ollama chat for knowledge extraction + embed for vectors)
- FileSystem behaviour + adapter (file reading for scanning)
- Knowledge entry schema + storage
- Embedding pipeline (entry → Ollama → vector → store)
- CLI entry point with init-mode branching (in-process, no daemon)

Items 1-4 in the sequence above are prerequisites to the first feature story. The init scan IS the integration test of the foundation — if it works, the core infrastructure is proven.

**Cross-Component Dependencies:**
- Provider behaviour shapes prompt assembly AND agent runner AND init scanner (knowledge extraction)
- FileSystem behaviour shapes file transactions AND agent runner AND init scanner
- Shell behaviour shapes validation pipeline AND init scanner (language command validation)
- LLM behaviour shapes planning engine AND execution AND thesis validation
- All behaviours shape test architecture

### Development Conventions

**Consumer-driven context APIs:** Design each context's public API for its actual consumers. List all queries each consumer needs before implementation. When tempted to reach into context internals, add a function to the public API — the temptation means the API is incomplete.

**Presenter convention:** Don't pass Ecto schemas directly to templates or JSON encoders — derive a map first. Code review rule, not an architectural module.

**Knowledge-not-code rule:** Context store entries must contain navigational knowledge (facts, decisions, gotchas, relationships), not code copies. Enforced at ingestion across init scan, post-task hygiene, and manual context operations.

## Implementation Patterns & Consistency Rules

### Guiding Principle

Consistency matters more than any specific convention choice. These patterns exist so that AI agents building different parts of Familiar produce code that looks like one person wrote it. When Elixir/Phoenix has a strong convention, follow it. When it doesn't, the choice below is the tiebreaker.

### Elixir/Phoenix Conventions (follow without exception)

- **Module naming:** `CamelCase` — `Familiar.Knowledge.Store`
- **Function/variable naming:** `snake_case` — `get_task`, `current_user`
- **File naming:** `snake_case.ex` matching module — `knowledge_store.ex`
- **Database:** plural snake_case tables (`knowledge_entries`), snake_case columns, Ecto default timestamps (`inserted_at`/`updated_at`)
- **Test files:** mirror `lib/` structure in `test/`, suffix `_test.exs`
- **Formatting:** `mix format` — no exceptions, no overrides

### Project-Specific Patterns (where Elixir doesn't dictate)

**Context public APIs:**
- Functions that find a single record: `fetch_*` returns `{:ok, record} | {:error, {:not_found, details}}`. Never raise, never return nil
- Functions that list records: `list_*` returns a list (empty list, not error, when none found)
- Functions that create/update: return `{:ok, record} | {:error, {type, details}}`
- Functions that delete: return `:ok | {:error, {type, details}}`

**JSON API responses:**
- Envelope: `{"data": ...}` for success, `{"error": {"type": "...", "message": "...", "details": {...}}}` for errors
- Field naming: `snake_case` in JSON (match Elixir, don't translate to camelCase)
- HTTP status codes: 200 for success, 404/422/500 for errors. No custom codes

**PubSub events:**
- Topic format: `"familiar:{context}:{entity}"` — e.g., `"familiar:work:task"`, `"familiar:execution:agent"`
- Event format: `{event_name, payload}` — e.g., `{:status_changed, %{task_id: 42, from: :ready, to: :in_progress}}`
- Event names: past tense atoms — `:completed`, `:failed`, `:status_changed`, `:progress_updated`

**LiveView patterns:**
- Event names in templates: `snake_case` strings — `"approve_spec"`, `"cancel_task"`
- Assigns: descriptive snake_case — `:current_task`, `:triage_entries`, `:search_query`
- Function components for stateless rendering. LiveComponent only when the component needs its own lifecycle (e.g., search picker with its own socket assigns)

**Error tuples:**
- Always `{:error, {atom_type, map_details}}` — never bare atoms, never strings
- Type atoms are domain-scoped: `:provider_unavailable`, `:validation_failed`, `:file_conflict`, `:not_found`, `:invalid_config`

**Logging:**
- Use `Logger` with appropriate levels: `:debug` for internal tracing, `:info` for operations, `:warning` for recoverable issues, `:error` for failures
- Structured metadata via `Logger.metadata/1` — always include `task_id` when in task context
- Never `IO.puts` for operational output — all output through formatters or Logger

### Enforcement

- `mix format` in CI — code that doesn't format doesn't merge
- `mix credo --strict` for style consistency
- Context boundary enforcement via `boundary` hex package (compile-time check that contexts don't reach into each other's internals)
- Code review checklist: fetch/list/create patterns followed? Error tuples consistent? PubSub topics namespaced?

## Project Structure & Boundaries

### Complete Project Directory Structure

```
familiar/
├── .formatter.exs
├── .gitignore
├── .credo.exs
├── mix.exs
├── mix.lock
├── README.md
├── LICENSE                          # AGPL-3.0
├── config/
│   ├── config.exs                   # Shared config
│   ├── dev.exs                      # Dev environment
│   ├── test.exs                     # Test env — Mox mocks, sandbox
│   ├── prod.exs                     # Prod environment
│   └── runtime.exs                  # Runtime config for releases
├── lib/
│   ├── familiar/
│   │   ├── application.ex           # OTP Application — supervision tree, crash recovery gate
│   │   ├── repo.ex                  # Ecto Repo — SQLite3 adapter, sqlite-vec extension loading
│   │   ├── error.ex                 # Recoverable?/1 policy function
│   │   │
│   │   ├── knowledge/               # Context store — FR8–FR19c
│   │   │   ├── knowledge.ex         # Public API: search/1, fetch_entry/1, store/1, health/0
│   │   │   ├── entry.ex             # Ecto schema — knowledge_entries table
│   │   │   ├── freshness.ex         # Freshness validation — stat files, auto-refresh
│   │   │   ├── hygiene.ex           # Post-task hygiene loop — knowledge capture, pruning
│   │   │   └── init_scanner.ex      # Project init scan — FR1–FR7d
│   │   │
│   │   ├── work/                    # Task management — FR32–FR37
│   │   │   ├── work.ex              # Public API: fetch_task/1, list_tasks/1, update_status/2
│   │   │   ├── epic.ex              # Ecto schema
│   │   │   ├── group.ex             # Ecto schema
│   │   │   ├── task.ex              # Ecto schema
│   │   │   ├── subtask.ex           # Ecto schema
│   │   │   ├── state_machine.ex     # Task state transitions — pure logic
│   │   │   ├── dependency_resolver.ex # Dependency ordering — pure logic
│   │   │   └── triage.ex            # Triage roll-up — pure logic
│   │   │
│   │   ├── planning/                # Planning & specification — FR20–FR31
│   │   │   ├── planning.ex          # Public API: start_plan/1, respond/2, get_spec/1
│   │   │   ├── engine.ex            # Planning conversation engine
│   │   │   ├── prompt_assembly.ex   # Pure function: context → prompt + metadata
│   │   │   ├── verification.ex      # Tool call log → verification marks
│   │   │   ├── spec.ex              # Ecto schema — spec frontmatter index
│   │   │   └── decomposer.ex        # Spec → task hierarchy
│   │   │
│   │   ├── execution/               # Task execution — FR38–FR56b
│   │   │   ├── execution.ex         # Public API: dispatch/1, cancel/1, status/0
│   │   │   ├── agent_runner.ex      # Supervised task execution
│   │   │   ├── tool_handler.ex      # Tool call dispatch (read_file, write_file, etc.)
│   │   │   ├── validation_pipeline.ex # Test/build/lint/coverage/duplicate checks
│   │   │   ├── self_repair.ex       # Autonomous retry logic — FR57b
│   │   │   └── execution_log.ex     # Ecto schema — tool calls, LLM responses
│   │   │
│   │   ├── files/                   # File operations — atomic writes, rollback
│   │   │   ├── files.ex             # Public API: write/3, rollback_task/1, pending_conflicts/0
│   │   │   ├── transaction.ex       # Ecto schema — file_transactions table
│   │   │   └── conflict.ex          # .fam-pending detection and resolution
│   │   │
│   │   ├── providers/               # LLM provider abstraction
│   │   │   ├── providers.ex         # Public API: chat/2, stream_chat/2, embed/1
│   │   │   ├── llm.ex              # Behaviour definition — callbacks
│   │   │   ├── ollama_adapter.ex    # Ollama implementation
│   │   │   ├── anthropic_adapter.ex # Anthropic implementation
│   │   │   └── stream_event.ex      # Common stream event types
│   │   │
│   │   ├── cli/                     # CLI client (daemon consumer, not domain)
│   │   │   ├── main.ex              # Entry point — parse args, dispatch
│   │   │   ├── http_client.ex       # Simple commands via req
│   │   │   ├── channel_client.ex    # Interactive commands via WebSocket
│   │   │   └── formatter.ex         # Terminal output formatting (--json, --quiet, pretty)
│   │   │
│   │   └── system/                  # System-level behaviours
│   │       ├── file_system.ex       # Behaviour: read, write, stat, delete
│   │       ├── local_file_system.ex # Production adapter
│   │       ├── shell.ex             # Behaviour: cmd/3
│   │       ├── real_shell.ex        # Production adapter
│   │       ├── notifications.ex     # Behaviour: notify/2
│   │       ├── notifier.ex          # Production adapter (terminal-notifier/notify-send)
│   │       ├── clock.ex             # Behaviour: now/0
│   │       └── system_clock.ex      # Production adapter
│   │
│   └── familiar_web/
│       ├── endpoint.ex              # Phoenix endpoint
│       ├── router.ex                # Routes — API + LiveView
│       ├── telemetry.ex
│       ├── api/                     # JSON API controllers
│       │   ├── health_controller.ex # GET /api/health — version, status
│       │   ├── status_controller.ex # GET /api/status — triage, progress
│       │   ├── task_controller.ex   # Task CRUD endpoints
│       │   ├── plan_controller.ex   # POST /api/plan — dispatch planning
│       │   ├── execution_controller.ex # POST /api/do — dispatch execution
│       │   ├── search_controller.ex # GET /api/search
│       │   ├── context_controller.ex # Context management endpoints
│       │   └── fallback_controller.ex # Error rendering
│       ├── channels/
│       │   ├── cli_channel.ex       # Interactive CLI channel (plan, fix)
│       │   └── execution_channel.ex # Execution progress streaming (watch)
│       ├── live/
│       │   ├── spec_live.ex         # Spec review view — approve/edit/reject
│       │   ├── triage_live.ex       # Triage dashboard — worst-first sort
│       │   ├── watch_live.ex        # Live activity feed
│       │   ├── library_live.ex      # Knowledge store browser
│       │   ├── search_component.ex  # Telescope-style picker overlay
│       │   ├── status_bar_component.ex # Persistent status bar
│       │   └── help_component.ex    # Keybinding reference overlay
│       ├── layouts/
│       │   ├── root.html.heex       # Minimal root — zero chrome
│       │   └── app.html.heex        # App layout — status bar only
│       └── static/
│           └── css/
│               └── app.css          # Custom minimal CSS — design tokens
├── priv/
│   ├── repo/
│   │   └── migrations/              # Ecto migrations
│   └── static/                      # Compiled static assets
├── test/
│   ├── test_helper.exs              # Mox setup, sandbox config
│   ├── support/
│   │   ├── mocks.ex                 # 6 Mox mock definitions
│   │   ├── fixtures/                # Canned LLM responses, sample projects
│   │   ├── generators.ex            # StreamData generators
│   │   └── factory.ex               # Test data factories
│   ├── familiar/
│   │   ├── knowledge/
│   │   │   ├── knowledge_test.exs   # Public API — Ecto sandbox
│   │   │   ├── freshness_test.exs   # Mocked filesystem + clock
│   │   │   └── init_scanner_test.exs
│   │   ├── work/
│   │   │   ├── state_machine_test.exs      # Pure logic + property tests
│   │   │   ├── dependency_resolver_test.exs # Pure logic + property tests
│   │   │   └── triage_test.exs
│   │   ├── planning/
│   │   │   ├── engine_test.exs             # Mocked LLM + sandbox
│   │   │   ├── prompt_assembly_test.exs    # Pure function + property tests
│   │   │   └── verification_test.exs       # Mocked filesystem + property tests
│   │   ├── execution/
│   │   │   ├── agent_runner_test.exs       # Mocked LLM/FS/Shell
│   │   │   ├── validation_pipeline_test.exs # Mocked shell + property tests
│   │   │   └── self_repair_test.exs
│   │   ├── files/
│   │   │   ├── transaction_test.exs        # Sandbox + property tests
│   │   │   └── conflict_test.exs           # Mocked filesystem + clock
│   │   ├── providers/
│   │   │   ├── ollama_adapter_test.exs     # Tagged :integration
│   │   │   ├── anthropic_adapter_test.exs  # Tagged :integration
│   │   │   └── provider_contract_test.exs  # Property-based contract
│   │   └── cli/
│   │       ├── http_client_test.exs        # Real Phoenix endpoint
│   │       └── channel_client_test.exs     # Real Phoenix channel
│   └── familiar_web/
│       ├── api/                             # Controller tests
│       ├── live/                            # LiveView tests
│       └── channels/                        # Channel tests
└── .github/
    └── workflows/
        └── ci.yml                           # mix format, credo, test, coverage
```

### Architectural Boundaries

**Context boundaries (enforced via `boundary` hex package):**

| Context | Depends On | Depended On By |
|---|---|---|
| `Familiar.Knowledge` | `System.FileSystem`, `System.Clock`, `Providers` (embedding) | `Planning`, `Execution` |
| `Familiar.Work` | (none — pure state management) | `Planning`, `Execution`, `Web` |
| `Familiar.Planning` | `Knowledge`, `Work`, `Providers`, `System.FileSystem` | `Web` (API + LiveView) |
| `Familiar.Execution` | `Knowledge`, `Work`, `Files`, `Providers`, `System.Shell` | `Web` (API + Channel) |
| `Familiar.Files` | `System.FileSystem`, `System.Clock` | `Execution` |
| `Familiar.Providers` | (external: Ollama, Anthropic) | `Knowledge`, `Planning`, `Execution` |
| `Familiar.CLI` | (external: HTTP/Channel to daemon) | (none — leaf client) |
| `FamiliarWeb` | All `Familiar.*` public APIs | (none — leaf UI) |

**Data boundaries:**
- All database access through Ecto Repo — no raw SQL outside migrations
- Each context owns its schemas — no cross-context schema references
- sqlite-vec queries through Knowledge context only

**API boundaries:**
- `/api/*` — JSON API for CLI and scripting
- LiveView routes — browser UI
- Channel: `familiar:cli` (interactive), `familiar:execution:*` (progress)

### FR Capability Area → Module Mapping

| Capability Area | Context | Key Modules |
|---|---|---|
| 1. Init & Config (FR1–FR7d) | `knowledge/` | `init_scanner.ex` |
| 2. Context Store (FR8–FR19c) | `knowledge/` | `knowledge.ex`, `entry.ex`, `freshness.ex`, `hygiene.ex` |
| 3. Planning (FR20–FR31) | `planning/` | `engine.ex`, `prompt_assembly.ex`, `verification.ex`, `decomposer.ex` |
| 4. Task Management (FR32–FR37) | `work/` | `work.ex`, `state_machine.ex`, `dependency_resolver.ex` |
| 5. Execution (FR38–FR47) | `execution/` | `agent_runner.ex`, `tool_handler.ex` |
| 6. Self-Validation (FR48–FR56b) | `execution/` | `validation_pipeline.ex`, `self_repair.ex` |
| 7. Recovery (FR57–FR57b) | `execution/` | `self_repair.ex` + `planning/engine.ex` (fix flow) |
| 8. Safety (FR58–FR64) | `execution/` + `files/` + `knowledge/` | Enforcement in tool_handler, transaction, ingestion |
| 9. Workflow Config (FR65–FR69) | Config loading at startup | `config/` + `.familiar/roles/`, `.familiar/workflows/` |
| 10. Web UI (FR71–FR79) | `familiar_web/live/` | 7 LiveView modules |
| 11. Thesis Validation (FR70) | `execution/` + `providers/` | Ablation hooks in prompt_assembly + agent_runner |

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:** All technology choices verified compatible. Phoenix 1.8 + LiveView 1.1 + ecto_sqlite3 + sqlite_vec 0.1 + ollama 0.9 + anthropix 0.6 form a coherent stack on the BEAM runtime.

**Pattern Consistency:** Hexagonal architecture with 6 testing ports aligns with external system boundaries. Ecto conventions, snake_case patterns, and context boundary enforcement all reinforce each other. No conflicting patterns found.

**Structure Alignment:** Domain-driven context structure maps 1:1 to capability areas. Test structure mirrors lib. Boundary dependency table enforces context isolation at compile time.

**Internal Consistency:** 4 contradictions found and resolved during validation — stale "unresolved" text removed, `--json` tier classification aligned, embedding async/blocking wording clarified, extensibility vs testing behaviours distinguished.

### Requirements Coverage ✅

**FR Coverage:** All 11 capability areas (87 FRs) have explicit module mapping in the project structure. No orphan FRs without architectural support.

**NFR Coverage:** All 7 NFR categories addressed by architectural decisions. Performance targets achievable with chosen stack. Reliability guaranteed by transaction log + crash recovery gate. Testability guaranteed by hexagonal ports.

**PRD Success Criteria Scoring:** Architecture scores 4.0/5.0 average against all 20 PRD success criteria. No criteria unaddressed. 4 gaps identified and resolved during validation: requirement coverage check mechanism, secret detection, init time budget, ablation comparison approach.

**Resolved During Validation:**
- FR30 (resume planning conversation): option (b) selected — persist message history in SQLite
- Tool call execution loop: defined as core agent runner loop (prompt → response → parse tool calls → execute → append results → repeat)
- `--json` promoted from Tier 3 deferral to foundational — implement on first command built
- CLI entry point flow: init runs in-process (no daemon), normal commands go through HTTP/Channel
- Common tool definition format: provider-agnostic tool schema documented
- Requirement coverage: checklist-based validation in pipeline
- Secret detection: regex-based structural scan before knowledge storage
- Init time budget: 5-minute target with batching and prioritization

**Remaining Unresolved:**
- WebSocket client library: verify `slipstream` or `fresh` maintenance status before implementation

### Implementation Readiness ✅

**Decision Completeness:** 6 critical/important decisions fully documented with versions, rationale, and affected components. 3 deferred decisions identified (release packaging, logging format, telemetry).

**Structure Completeness:** Full directory tree with ~50 files defined. Every module has a description, every context has a public API, every test file has its test strategy.

**Pattern Completeness:** Naming, API format, PubSub events, LiveView patterns, error tuples, logging — all specified. Enforcement via `mix format`, `mix credo`, `boundary` package.

### Architecture Completeness Checklist

**✅ Requirements Analysis**
- [x] Project context analyzed (6 elicitation rounds + party mode)
- [x] Scale and complexity assessed (Medium-High, tier-driven)
- [x] Technical constraints identified (solo dev, Apple M1/M2, AGPL-3.0)
- [x] Cross-cutting concerns mapped (9 concerns, prioritized)

**✅ Architectural Decisions**
- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined (HTTP + Channel hybrid)
- [x] Performance considerations addressed (blocking init, freshness gate, init time budget)
- [x] Extensibility architecture defined (6 behaviour seams, domain-agnostic principle)
- [x] Testing architecture defined (6 ports, Mox, Ecto sandbox, property-based, coverage targets)

**✅ Implementation Patterns**
- [x] Naming conventions established (Elixir standard + project-specific)
- [x] Structure patterns defined (context public APIs, fetch/list/create)
- [x] Communication patterns specified (PubSub topics, stream events)
- [x] Process patterns documented (error tuples, logging, enforcement)

**✅ Project Structure**
- [x] Complete directory structure defined
- [x] Component boundaries established (context dependency table)
- [x] Integration points mapped (API, Channel, PubSub)
- [x] Requirements to structure mapping complete (11 capability areas → modules)

**✅ Validation**
- [x] Red Team adversarial review (5 rounds, 5 gaps found and fixed)
- [x] Reverse engineering from first story (chicken-and-egg resolved, prerequisite chain documented)
- [x] Hindsight reflection (tool call loop, conversation persistence, --json promotion)
- [x] Self-consistency check (4 contradictions found and fixed)
- [x] PRD success criteria scoring (4.0/5.0, all gaps addressed)

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High — validated through adversarial review, reverse engineering, hindsight analysis, consistency checks, and success criteria scoring

**Key Strengths:**
- Triple-purpose boundaries (extensibility + testability + context isolation)
- Hexagonal architecture makes every module testable in isolation
- Blocking init with knowledge-not-code strategy produces high-quality context from day one
- Crash recovery gate in Application.start handles every analyzed failure mode
- Tool call execution loop is explicitly defined — the core of what the agent runner does
- Architecture shaped by MVP tiers, extensible to multi-agent and domain-agnostic

**Areas for Future Enhancement:**
- Context injection priority tiers (if baseline measurement shows convention miss rate)
- Automated ablation comparison scoring (post-MVP if thesis validates)
- Multi-agent supervision topology (Registry + DynamicSupervisor when extending)
- `boundary` package integration verification

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented
- Use implementation patterns consistently across all components
- Respect context boundaries — never import from another context's internals
- Every new module needs tests (Mox for external boundaries, Ecto sandbox for DB, pure unit for logic)
- `--json` support on every command from day one
- Refer to this document for all architectural questions

**First Implementation Priority:**
1. `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard`
2. Strip Tailwind, add sqlite_vec + req + toml + yaml_elixir + stream_data + mox + boundary
3. Domain context structure + Ecto schemas + migrations
4. 6 testing port behaviours + Mox mock definitions
5. Ollama provider adapter (chat + embed)
6. Init scanner — the first feature story and integration test of the foundation

## Architecture Addendum (2026-04-03): Multi-Agent Harness Architecture

### Architectural Reframing

**Familiar is a multi-agent harness** that ships with an opinionated default set of workflows, roles, and skills for software development. The Elixir/OTP codebase provides the **agentic execution environment** — it is not a planning tool, a coding assistant, or a task runner. It is the runtime that hosts agents, provides tools, enforces safety, and manages state. What those agents do is defined entirely in user-editable markdown files.

**The Elixir code provides:**
- `AgentProcess` — a generic GenServer that executes any agent role via a tool-call loop
- `WorkflowRunner` — sequences agents through workflow steps (interactive + autonomous)
- `ToolRegistry` — maps tool names to Elixir implementations; the bridge between LLM intent and system action
- `AgentSupervisor` — DynamicSupervisor for all agent processes (the core OTP primitive)
- Safety enforcement at the tool layer (project sandboxing, git protection, deletion constraints)
- Provider abstraction (Ollama, Anthropic) behind a common behaviour
- PubSub event infrastructure for status streaming

**Two systems provided to agents as tools/skills:**
- **Knowledge Store** — semantic search, knowledge capture, freshness validation. Agents access this via tools (`search_context`, `store_context`, `list_entries`, `check_freshness`)
- **Task Manager** (post-MVP) — structured Ecto work hierarchy, state machine, dependency resolution. MVP alternative: agents track tasks in markdown files via `read_file`/`write_file` in `.familiar/tasks/`

**Additional tools provided by the execution environment:**
- File operations (`read_file`, `write_file`, `delete_file`, `list_files`) via the file transaction module
- Shell commands (`run_command`) restricted to configured test/build/lint commands
- Agent orchestration (`spawn_agent`, `monitor_agents`, `broadcast_status`) for the PM role
- Workflow signals (`signal_ready`, `signal_phase_transition`) for step transitions

**Everything else is markdown:**
- **Roles** (`.familiar/roles/*.md`) — agent personas, system prompts, skill references
- **Skills** (`.familiar/skills/*.md`) — capability bundles, tool permissions, instructions
- **Workflows** (`.familiar/workflows/*.md`) — step sequences, agent assignments, interaction modes

This means **planning is not a special system** — it is a workflow (`feature-planning.md`) executed by agents (analyst, librarian, spec-writer, reviewer) using the same AgentProcess and tool-call loop that executes code implementation, task fixing, and any user-defined workflow. There is no `Engine` module that knows about planning phases. There is a generic workflow runner that sequences agents through steps defined in markdown.

**Context:** During Epic 3 implementation, architectural review identified that: (1) multi-agent orchestration is a core differentiator of the BEAM/OTP platform choice and must be MVP scope, (2) agent prompts hard-coded in Elixir should load from user-editable markdown files, and (3) the execution environment must be built before domain-specific workflows (including planning) can run on top of it.

### Superseded Decisions

The following statements from the original architecture document are **superseded** by this addendum:

| Original | Superseded By |
|---|---|
| Line 61: "MVP spawns one agent process at a time. Sequential by policy, not by architecture." | Decision A1: Parallel execution is MVP scope with configurable concurrency |
| Line 242: "Sequential execution only (MVP)" | Decision A1: Parallel execution is MVP scope |
| Line 253: "Single coding agent (analyst/coder/reviewer roles via role files)" | Decision A1: Multiple concurrent agents, each an AgentProcess with a role file |
| Line 261: "Do NOT pre-build behaviours. Build the MVP coding implementation first as concrete modules" | Decision A2: One generic AgentProcess, no per-role Elixir modules needed |
| Line 278: "Parsed but ignored for MVP: `parallel: true` flag on workflow steps" | Decision A1: Parallel flag honored in MVP |
| Line 1031: "Multi-agent supervision topology (Registry + DynamicSupervisor when extending)" | Decision A1: Built now, not deferred |
| Lines 58-64: Planning Engine as a core process with conversation loop | Decision A3: Planning is a workflow, not a bespoke system. No `Engine` module — the workflow runner sequences agents. |
| Line 64: "Prompt Assembly Pipeline — pure function module" with hard-coded prompt | Decision A3: System prompts come from role files. PromptAssembly assembles role prompt + context + history — it does not define the prompt content. |
| Epic ordering: Epic 3 (Planning) before Epic 5 (Execution) | Decision A4: Execution environment built first. Planning runs on top as a workflow. |

### Decision A1: Multi-Agent Orchestration Topology (MVP)

**Decision:** Single generic agent executor (`AgentProcess` GenServer) under one shared `DynamicSupervisor`. All agent differentiation lives in role markdown files, not Elixir code. A project-manager role orchestrates parallel worker agents.

**Core principle:** One GenServer module, many role files. Creating a new agent type means creating a markdown file — no Elixir code required.

**Supervision topology:**

```
Familiar.Supervisor (one_for_one)
├── ... (existing: Telemetry, Repo, TaskSupervisor, Migrator, RecoveryGate, PubSub, etc.)
│
├── Familiar.AgentSupervisor (DynamicSupervisor)     ← NEW (consolidates LibrarianSupervisor)
│   ├── AgentProcess (role: "project-manager", task: batch_spec)
│   │     ├── AgentProcess (role: "coder", task: implement_auth)
│   │     ├── AgentProcess (role: "coder", task: add_tests)
│   │     ├── AgentProcess (role: "librarian", task: context_query)
│   │     └── AgentProcess (role: "archivist", task: knowledge_capture)
│   └── ... (any user-defined role)
```

All agents — project manager, coder, reviewer, librarian, archivist, and any user-created custom roles — are instances of the same `AgentProcess` GenServer, differentiated entirely by their loaded role file.

**AgentProcess GenServer:**

```elixir
# Conceptual structure — one module for ALL agents
defmodule Familiar.Execution.AgentProcess do
  use GenServer

  # init/1: load role file, initialize state
  # handle_continue(:execute, state): enter tool-call loop
  # handle_info({:tool_result, ...}, state): process tool result, continue loop
  # handle_info({:DOWN, ...}, state): handle monitored child crash
  # terminate/2: clean shutdown, report final status
end
```

The GenServer code is identical regardless of role. The LLM sees a different system prompt (from the role file), has access to different tools (from the role's skill references), and operates under different constraints (from skill metadata). The Elixir execution loop is the same.

**Agent spawning:**

```elixir
# All agents start the same way — role file is the only differentiator
AgentProcess.start_link(role: "coder", task: task, parent: pm_pid, opts: opts)
AgentProcess.start_link(role: "project-manager", task: batch, parent: nil, opts: opts)
AgentProcess.start_link(role: "librarian", task: query, parent: caller_pid, opts: opts)
AgentProcess.start_link(role: "my-custom-reviewer", task: review, parent: pm_pid, opts: opts)
```

**Project Manager as an agent:**

The project manager is an AgentProcess loaded with the `project-manager` role. It has agentic responsibilities:
- **Summarizes** worker results for the user ("3 tasks done, auth handler wrote 4 files")
- **Makes decisions** about failure handling ("stale context → retry" vs "ambiguous → escalate")
- **Decomposes** work when tasks need further breakdown
- **Routes and transforms** status messages (not just raw forwarding)

The PM's role file defines these responsibilities via its system prompt and available skills. Its tools include orchestration-specific operations (`spawn_agent`, `monitor_agents`, `broadcast_status`) plus standard file tools (`read_file`, `write_file`, `list_files`) for managing task markdown files. It participates in the same tool-call loop as any other agent — the LLM decides when to spawn workers, how to handle failures, and what to report to the user.

**Message flow:**

```
Engine.dispatch_batch(task_ids, opts)
  → DynamicSupervisor.start_child(AgentSupervisor,
      {AgentProcess, role: "project-manager", task: %{task_ids: ids, ...}})

  ProjectManager (AgentProcess, role: "project-manager"):
    → LLM receives task graph, decides execution order
    → Tool call: spawn_agent(role: "coder", task: task_1)
    → Tool call: spawn_agent(role: "coder", task: task_2)   # parallel
    → Receives: {:worker_status, pid, %{type: :reading_file, detail: "auth.ex"}}
    → Tool call: broadcast_status("Reading auth.ex for task #1")
    → Receives: {:worker_complete, pid, result}
    → Tool call: spawn_agent(role: "archivist", task: result.artifacts)
    → LLM evaluates: dependent tasks now unblocked?
    → Tool call: spawn_agent(role: "coder", task: task_3)   # was blocked on task_1
    → ... continues until batch complete
    → Tool call: broadcast_status("Batch complete: 5/5 tasks, 12 files modified")
    → Terminates
```

**File conflict prevention:**

Before the PM spawns a worker, it checks the worker's intended files (from task decomposition) against files claimed by running workers. This is state in the PM's GenServer — a map of `%{pid => [file_paths]}`. If overlap exists, the PM defers the task until the holder completes. On PM crash, the file transaction module's pre-write stat check (Story 5.2) provides the safety net — double protection.

**Concurrency configuration:**

```toml
# .familiar/config.toml
[execution]
max_parallel_agents = 3    # Default: 3. Set to 1 for sequential-only
```

Setting `max_parallel_agents = 1` reproduces sequential behavior. The architecture is always concurrent — the policy is configurable. The PM role file references this config when deciding how many workers to spawn simultaneously.

**CLI/Web as UserManager:**

The CLI process and Phoenix Channel already serve the UserManager function: they own the user session, receive status via PubSub, and format output. No separate UserManager GenServer is needed for MVP. The PM broadcasts status to PubSub; the CLI/Channel subscribes and displays. The GenServer version becomes relevant post-MVP when persistent session state across multiple CLI invocations is needed.

**Consolidation of LibrarianSupervisor:**

The existing `Familiar.LibrarianSupervisor` is replaced by `Familiar.AgentSupervisor`. The Librarian becomes an AgentProcess with `role: "librarian"` — same GenServer, same supervision, role file provides the multi-hop retrieval instructions.

**Rationale:** The BEAM's process model makes N ephemeral agents as easy to supervise as 1. The Librarian GenServer (already implemented) proves the pattern. Making the PM an agent (not a special coordinator) means the orchestration logic is in the role file — users can customize PM behavior, and the system has exactly one execution model to maintain. One GenServer module is simpler to test, debug, and reason about than N specialized modules.

### Decision A2: Role & Skill File System

**Decision:** Agent behavior is defined entirely by user-editable markdown files in `.familiar/roles/` and `.familiar/skills/`. No agent-specific Elixir code. Three-tier capability model: Role → Skills → Tools.

**Three-tier model:**

```
Role (persona + system prompt)     → defines WHO the agent is
  └── Skills (capability bundles)  → defines WHAT the agent can do
       └── Tools (atomic ops)      → defines HOW actions execute
```

A role references skills by name. A skill references tools by name. Tools are registered in the Elixir tool registry (the only part that requires code — tool implementations are Elixir functions). Roles and skills are pure markdown.

**File format — roles:**

```markdown
# .familiar/roles/librarian.md
---
name: librarian
description: Multi-hop knowledge retrieval and summarization
model: default
lifecycle: ephemeral
skills:
  - search_knowledge
  - summarize_results
---

You are a knowledge librarian. Your job is to find and summarize relevant
context from the project's knowledge store.

## Search Refinement

Given a query and search results, identify what information is missing.
If results adequately cover the query, signal "SUFFICIENT".
Otherwise, return a refined search query to fill the gaps.

## Summarization

Summarize search results into a concise context block relevant to the query.
Cite sources using "[source_file]" after each claim.
Keep the summary focused and actionable.
```

```markdown
# .familiar/roles/project-manager.md
---
name: project-manager
description: Orchestrates task execution, monitors workers, summarizes progress
model: default
lifecycle: batch
skills:
  - dispatch_tasks
  - monitor_workers
  - summarize_progress
  - evaluate_failures
---

You are a project manager coordinating task execution for a software project.

## Task Orchestration
- You receive a batch of tasks with dependency information
- Dispatch independent tasks in parallel (up to the configured concurrency limit)
- Track completion and unblock dependent tasks when their dependencies finish

## Status Reporting
- Provide concise status updates as workers progress
- Translate technical details into actionable summaries
- Report completion with: tasks done, files modified, tests added

## Failure Evaluation
- When a worker fails, evaluate whether the failure is recoverable
- Stale context or transient provider issues: retry automatically (max 1 retry)
- Ambiguous failures: escalate to user with your analysis and options
- 3+ same-type failures in a batch: stop retrying that type (circuit breaker)
```

```markdown
# .familiar/roles/coder.md
---
name: coder
description: Implements features and fixes following project conventions
model: default
lifecycle: ephemeral
skills:
  - implement
  - test
  - research
---

You are a software developer implementing features and fixes.

## Approach
- Follow established code patterns and conventions from the knowledge store
- Write tests alongside implementation
- Keep changes focused and minimal — do not refactor surrounding code
- Document significant decisions for the knowledge store

## Safety
- Only modify files within the project directory
- Only create files that are necessary for the task
- Run tests after making changes to verify correctness
```

```markdown
# .familiar/roles/archivist.md
---
name: archivist
description: Extracts and captures knowledge from completed work
model: default
lifecycle: ephemeral
skills:
  - extract_knowledge
  - capture_gotchas
---

You are an archivist responsible for capturing institutional knowledge
from completed work.

## Knowledge Extraction
- From successful task output: extract conventions applied, decisions made,
  relationships discovered
- From failure context: extract gotchas, edge cases, patterns that caused confusion
- NEVER capture raw code — capture the knowledge ABOUT the code

## Quality Rules
- Each knowledge entry must be a natural language description, not code
- Cite source files using "[file_path]" format
- Keep entries focused and actionable — one concept per entry
- Check for duplicates before storing — update existing entries rather than
  creating near-duplicates
```

**Role frontmatter fields:**

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique identifier, matches filename without extension |
| `description` | yes | One-line description shown in `fam roles` listing |
| `model` | no | Model preference: `default`, `local`, `frontier`, or specific model name. Default: `default` (uses config) |
| `lifecycle` | no | `ephemeral` (dies after one task, default), `batch` (lives for batch duration), `session` (lives for user session) |
| `skills` | yes | List of skill names this role can use |

**File format — skills:**

```markdown
# .familiar/skills/search_knowledge.md
---
name: search_knowledge
description: Semantic search across the knowledge store
tools:
  - search_context
  - read_file
constraints:
  max_iterations: 5
  read_only: true
---

Search the knowledge store for entries relevant to the given query.
Use semantic embedding to find related entries. If initial results
are sparse (fewer than 3 results), refine the query and search again.
Return raw results with source citations.
```

```markdown
# .familiar/skills/dispatch_tasks.md
---
name: dispatch_tasks
description: Spawn and coordinate worker agents for task execution
tools:
  - spawn_agent
  - broadcast_status
  - read_file
  - write_file
  - list_files
constraints:
  max_parallel: config.execution.max_parallel_agents
---

Dispatch tasks to worker agents respecting dependency ordering.
Read task files from .familiar/tasks/ to determine dependencies
and status. Only dispatch tasks whose dependencies are complete.
Track intended files per worker to prevent conflicts.
Update task file status as workers complete.
```

**Skill frontmatter fields:**

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique identifier, matches filename without extension |
| `description` | yes | One-line description |
| `tools` | yes | List of tool names from the tool registry this skill may invoke |
| `constraints` | no | Map of constraint key-values: `read_only`, `max_iterations`, `max_parallel`, etc. |

The skill body is appended to the agent's prompt when that skill is active, providing specific instructions for how to use the skill's tools.

**Tool registry (Elixir code — the only non-markdown layer):**

Tools are the atomic operations that agents invoke via the LLM tool-call interface. Each tool is an Elixir function registered in the tool registry. This is the only part that requires code changes to extend.

MVP tool registry:

| Tool | Context | Description |
|---|---|---|
| `read_file` | Files | Read a project file (also used by PM for task markdown) |
| `write_file` | Files | Write via transaction module (also used by PM for task status updates) |
| `delete_file` | Files | Delete (own-task files only) |
| `run_command` | System | Execute allowed shell commands (test/build/lint) |
| `search_context` | Knowledge | Semantic search of knowledge store |
| `store_context` | Knowledge | Insert knowledge entry |
| `list_files` | Files | List project files matching pattern |
| `spawn_agent` | Execution | Start a new AgentProcess under AgentSupervisor |
| `monitor_agents` | Execution | Query status of running agents |
| `broadcast_status` | Execution | Push status update to PubSub |
| `signal_ready` | Execution | Signal workflow runner that current step is complete |

Tools enforce safety constraints at the implementation level (project directory sandboxing, git protection, deletion restrictions per Story 5.3). A role/skill file cannot grant permissions that the tool implementation doesn't allow.

**Runtime loading module:**

A new module `Familiar.Roles` provides:

```elixir
# Public API
Familiar.Roles.load_role(name)      # → {:ok, %Role{}} | {:error, {:role_not_found, ...}}
Familiar.Roles.load_skill(name)     # → {:ok, %Skill{}} | {:error, {:skill_not_found, ...}}
Familiar.Roles.list_roles()         # → {:ok, [%Role{}]}
Familiar.Roles.list_skills()        # → {:ok, [%Skill{}]}
Familiar.Roles.validate_role(name)  # → :ok | {:error, {:invalid_role, %{reason: ...}}}
Familiar.Roles.validate_skill(name) # → :ok | {:error, {:invalid_skill, %{reason: ...}}}
```

Role and skill structs:

```elixir
%Familiar.Roles.Role{
  name: "coder",
  description: "Implements features and fixes following project conventions",
  model: "default",
  lifecycle: :ephemeral,
  skills: ["implement", "test", "research"],
  system_prompt: "You are a software developer..."   # body of the markdown file
}

%Familiar.Roles.Skill{
  name: "implement",
  description: "Write and modify code files",
  tools: ["read_file", "write_file", "run_command", "search_context"],
  constraints: %{},
  instructions: "..."   # body of the markdown file
}
```

**Integration with prompt assembly:**

`PromptAssembly` currently uses a hard-coded `@planning_system_prompt` module attribute. This changes to accept a loaded role:

```elixir
# Before (hard-coded):
PromptAssembly.assemble(context_block, conversation_history)

# After (role-driven):
{:ok, role} = Roles.load_role("analyst")
PromptAssembly.assemble(context_block, conversation_history, role: role)
```

The `@planning_system_prompt` module attribute is removed. The prompt comes from `.familiar/roles/analyst.md`.

**Integration with Librarian:**

The two inline prompts in `librarian.ex` (search refinement + summarization) move to `.familiar/roles/librarian.md`. When the Librarian is migrated to AgentProcess, it loads this role file on init. Until that migration (Epic 5), the Librarian can use `Roles.load_role("librarian")` to read its prompt from the file instead of the inline string.

**Default files update:**

`Knowledge.DefaultFiles.install/1` is updated to install:
- `.familiar/roles/` — analyst, coder, reviewer, librarian, archivist, project-manager (with proper YAML frontmatter)
- `.familiar/skills/` — implement, test, research, review_code, search_knowledge, summarize_results, extract_knowledge, capture_gotchas, dispatch_tasks, monitor_workers, summarize_progress, evaluate_failures

These replace the current stub role files (which lack frontmatter and skill references).

**User customization:**

Users can:
- Edit any existing role/skill file to customize agent behavior
- Create new roles by adding a `.md` file to `.familiar/roles/`
- Create new skills by adding a `.md` file to `.familiar/skills/`
- A custom role is immediately usable: `fam do #N --role my-custom-role`
- Reference custom roles in workflow step definitions

**Critical boundary — skills define intent, safety enforces permission:**

Skills define what an agent is *instructed* to do. Safety enforcement (Story 5.3) defines what an agent is *permitted* to do. A skill file lists tools the agent may request — the tool implementation validates each invocation against safety constraints. A malicious or misconfigured skill file cannot bypass project directory sandboxing, git protection, or deletion restrictions. Skill files are prompt content, not permission grants.

**Validation on load:**

When the daemon starts (or when a role/skill file is modified), validation runs:
- Role references skills that exist in `.familiar/skills/`
- Skills reference tools that exist in the tool registry
- Required frontmatter fields present (`name`, `description`, `skills`/`tools`)
- YAML frontmatter parses without errors
- Clear error messages per FR67: "Role 'my-role' references skill 'foo' which does not exist in .familiar/skills/"

**Rationale:** Hard-coding agent behavior in Elixir means every new agent type requires a code change, a compilation, and a release. Markdown files are editable in any text editor, versionable in git, and inspectable without Elixir knowledge. The three-tier model (Role → Skills → Tools) separates persona from capability from implementation. This directly addresses FR65-FR66 and makes the agent system user-extensible from day one.

### Decision A3: Planning as a Workflow

**Decision:** Planning is not a bespoke system. It is a workflow definition executed by agents through the generic workflow runner. The `Engine`, `PromptAssembly` (prompt content), and `Librarian` (GenServer) modules are replaced by AgentProcess instances loaded with role files.

**The planning workflow:**

```markdown
# .familiar/workflows/feature-planning.md
---
name: feature-planning
description: Plan a new feature from description to approved spec
trigger: plan
steps:
  - name: context-retrieval
    role: librarian
    mode: autonomous
    output: context_block
  - name: planning-conversation
    role: analyst
    mode: interactive
    input: context_block
    output: conversation_decisions
  - name: spec-generation
    role: spec-writer
    mode: autonomous
    input: [context_block, conversation_decisions]
    output: spec_draft
  - name: verification
    role: reviewer
    mode: autonomous
    input: spec_draft
    output: verified_spec
  - name: approval
    mode: interactive
    input: verified_spec
    output: approved_spec
---
```

Each step is an AgentProcess with a role file, using the same tool-call loop as code implementation. The workflow runner:
1. Starts the first step's agent with the workflow context
2. Passes each step's output as input to subsequent steps
3. Handles interactive mode (multi-turn conversation via Channel) vs. autonomous mode (run to completion)
4. Manages step transitions — agents signal readiness via a `signal_ready` tool call instead of magic string prefixes

**What survives from Epic 3 (already built):**

| Module | Lines | Survival | Notes |
|---|---|---|---|
| `verification.ex` | 216 | 100% | Pure functional, zero coupling to conversation model |
| `trail.ex` | 125 | 100% | PubSub infrastructure, used by workflow runner for events |
| `trail_formatter.ex` | 110 | 100% | Pure formatter, gains new event type clauses |
| `spec_review.ex` | 259 | ~95% | Approval logic independent of orchestration |
| `spec_generator.ex` | 465 | ~40% | Tool handlers (`file_read`, `knowledge_search`) extract to tool registry; frontmatter/title/slug utils survive; tool loop and prompt die |
| `librarian.ex` | 237 | ~30% | Search merge/format helpers extract; GenServer + prompts replaced by AgentProcess + role file |
| `engine.ex` | 273 | ~15% | Only DB helper functions survive |
| `prompt_assembly.ex` | 97 | ~5% | Only `normalize_history/1` survives; prompt content moves to role files |

**~700 lines of infrastructure survive.** Verification, trail, review, and tool handler implementations carry forward into the new system. **~550 lines of orchestration and hard-coded prompts are replaced** by the workflow runner + role files.

**How LLM reasoning replaces programmatic logic:**

| Current Code | Replaced By |
|---|---|
| `length(results) < @gap_threshold` (numeric check) | Librarian LLM evaluates "do these results cover the query domain?" |
| `String.starts_with?(response, "[SPEC_READY]")` (magic string) | Analyst calls `signal_ready` tool when it judges conversation is complete |
| `@planning_system_prompt` question count rules (`3-5` / `0-2`) | Analyst role file says "ask as many questions as needed, no more" — LLM calibrates |
| `Verification.extract_claims/1` regex for file paths | Reviewer agent identifies verifiable claims semantically (can still use `verification.ex` as a tool) |
| `@max_hops 3` compiled constant | Librarian role file suggests "refine up to 3 times" — LLM stops sooner if coverage is good |
| `@spec_generation_prompt` fixed section requirements | Spec-writer role file describes good spec structure — user can customize per project |

**PromptAssembly survives as infrastructure, not content:**

`PromptAssembly` is not deleted — it is refactored. It no longer defines the system prompt (that comes from the role file). It becomes a pure function that assembles: role system prompt (from file) + skill instructions (from files) + context block + conversation history + provider-specific formatting → message list. The assembly logic survives. The prompt content does not.

**Rationale:** The BMAD framework that built Familiar demonstrates the pattern: workflows defined in markdown, executed by LLMs, with the LLM as the reasoning engine for decisions that are currently hard-coded. Familiar should implement the same pattern. Planning, implementation, review, and fix are all workflows. The Elixir code is the execution environment — not the domain logic.

### Decision A4: Execution-First Epic Ordering

**Decision:** The agentic execution environment must be built before domain-specific workflows (including planning) can run on top of it.

**Revised epic order:**

```
Phase 1 — Foundation (done):
  Epic 1: Project Foundation & Initialization (done)
  Epic 2: Knowledge Store & Context Management (done)
  Epic 3: Planning (stories 3-1 through 3-4 done — infrastructure survives)

Phase 2 — Agent Harness:
  Epic 4.5: Role & Skill File System (load/validate roles, skills; migrate inline prompts)
  Epic 5:   Agent Execution (AgentProcess, tool registry, workflow runner, PM agent, safety)

Phase 3 — Workflows on the Harness:
  Epic 3r: Planning Workflow (migrate planning to workflow runner; stories 3-5, 3-6, 3-7 run here)
  Epic 6:  Recovery Workflow (fam fix as a workflow)
  Epic 7:  Web UI
  Epic 8:  CLI Management & Session Handling

Post-MVP:
  Epic 4:  Task Management (structured Ecto hierarchy, state machine, dependency resolver)
```

**Key changes:**
- **Epic 4 (Task Management) moved to post-MVP.** The structured Ecto-based work hierarchy (state machine, dependency resolver, four-level hierarchy) is a convenience, not a foundation. Agents can track tasks in markdown files using `read_file`/`write_file` — the same tools they use for code. The PM agent manages work by reading and writing `.familiar/tasks/` markdown files, just as a human PM would. The structured task system becomes a nice upgrade when warranted, not a prerequisite.
- Epic 3 stories 3-5 through 3-7 move to Phase 3 as "Epic 3r" (planning revisited) — they run planning as a workflow on the execution environment
- Epic 5 must complete before any workflow can execute, including planning
- Epic 4.5 (role/skill files) is the sole prerequisite for Epic 5 (AgentProcess loads roles)
- The planning workflow definition (`feature-planning.md`) becomes the integration test of Epic 5 — validating the execution environment against a real workflow that already has working test infrastructure
- **PM agent tools simplified:** No `query_task_graph` or `update_task_status` tools needed for MVP. The PM uses `read_file`, `write_file`, `list_files` on task markdown files. The `spawn_agent`, `monitor_agents`, and `broadcast_status` tools remain.

**What happens to already-built Epic 3 code:**
- Stories 3-1 through 3-4 are committed and tested. The infrastructure (verification, trail, review, tool handlers) is reusable.
- When Epic 3r runs, it migrates the surviving code into the new architecture and replaces the orchestration layer.
- Tests survive and are adapted — they validate the same behavior through the new execution model.
- No code is deleted until Epic 3r replaces it with equivalent workflow-driven behavior.

**Rationale:** The agent harness is the product. The task manager is a feature. Build the harness first, validate it with real workflows, then add structured task tracking when the overhead is justified by scale. Markdown task files are sufficient for the 50-task baseline phase.

### Updated Supervision Tree

```
Familiar.Supervisor (one_for_one)
├── FamiliarWeb.Telemetry
├── Familiar.Repo
├── {Task.Supervisor, name: Familiar.TaskSupervisor}
├── Familiar.AgentSupervisor (DynamicSupervisor)     ← REPLACES LibrarianSupervisor
│   └── AgentProcess instances (any role)
├── {Ecto.Migrator, ...}
├── Familiar.Daemon.RecoveryGate
├── {DNSCluster, ...}
├── {Phoenix.PubSub, name: Familiar.PubSub}
├── Familiar.Daemon.Server
└── FamiliarWeb.Endpoint
```

Changes from current `application.ex`:
- `Familiar.LibrarianSupervisor` renamed to `Familiar.AgentSupervisor` (same DynamicSupervisor, broader scope)
- No other supervision tree changes needed — the DynamicSupervisor pattern is already in place

### Updated Directory Structure (Additions Only)

```
lib/familiar/
  roles/                          # NEW context — role & skill file loading
  │ ├── roles.ex                  # Public API: load_role/1, list_roles/0, validate_role/1
  │ ├── role.ex                   # Struct: %Role{name, description, model, lifecycle, skills, system_prompt}
  │ └── skill.ex                  # Struct: %Skill{name, description, tools, constraints, instructions}
  │
  execution/
  │ ├── agent_process.ex          # NEW — Generic agent GenServer (one module for ALL roles)
  │ ├── tool_registry.ex          # NEW — Maps tool names to implementation functions
  │ ...

.familiar/
  roles/                          # UPDATED — proper frontmatter, system prompts as body
  │ ├── analyst.md                # Planning conversation agent
  │ ├── coder.md                  # Code implementation agent
  │ ├── reviewer.md               # Code review agent
  │ ├── librarian.md              # Knowledge retrieval agent
  │ ├── archivist.md              # Knowledge capture agent
  │ └── project-manager.md        # Batch orchestration agent
  │
  skills/                         # NEW — capability bundle definitions
  │ ├── implement.md
  │ ├── test.md
  │ ├── research.md
  │ ├── review_code.md
  │ ├── search_knowledge.md
  │ ├── summarize_results.md
  │ ├── extract_knowledge.md
  │ ├── capture_gotchas.md
  │ ├── dispatch_tasks.md
  │ ├── monitor_workers.md
  │ ├── summarize_progress.md
  │ └── evaluate_failures.md
```

### Impact on Existing Epics

**Epic 3 (Planning) — completed stories 3-1 through 3-4:**
Infrastructure survives: `verification.ex` (100%), `trail.ex` (100%), `trail_formatter.ex` (100%), `spec_review.ex` (~95%), tool handler implementations from `spec_generator.ex`. Orchestration and prompts (`engine.ex`, `prompt_assembly.ex` prompt content, `librarian.ex` GenServer) are replaced when planning migrates to a workflow in Epic 3r. No code is deleted until Epic 3r provides equivalent workflow-driven behavior. Tests survive and validate the same behavior through the new execution model.

**Epic 3 stories 3-5 through 3-7 → become Epic 3r (Phase 3):**
These stories (task decomposition, conflict detection, integration test) move to after Epic 5 completes. They execute planning as a workflow on the execution environment. The integration test (3-7) becomes the validation that the workflow runner correctly executes the `feature-planning.md` workflow end-to-end.

**Epic 4 (Task Management) — moved to post-MVP.** The structured Ecto work hierarchy is a convenience, not a prerequisite. Agents track tasks in markdown files using `read_file`/`write_file`. The PM reads `.familiar/tasks/` to determine dependencies and status. When the structured system is built (post-MVP), it replaces markdown task files with Ecto schemas and adds `query_task_graph`, `update_task_status` tools to the registry.

**Epic 4.5 (Role & Skill File System):** Unchanged — prerequisite for Epic 5. Roles context, file loading, default files, inline prompt migration.

**Epic 5 (Agent Execution):**
- **Story 5.1:** Builds `Execution.AgentProcess` — the single generic GenServer for all agents. Tool-call loop via `handle_continue`/`handle_info`. Role loaded from `.familiar/roles/` on init. `ToolRegistry` maps tool names to Elixir implementations.
- **Story 5.2:** File transaction module + file claim registration for parallel conflict prevention.
- **Story 5.3:** Safety enforcement at the tool layer.
- **Story 5.4:** Task dispatch. PM is an AgentProcess with `role: "project-manager"`. Parallel execution with configurable concurrency.
- **Story 5.5:** Workflow runner. Sequences agents through workflow step definitions. Handles interactive/autonomous modes, context passing between steps, phase transition signals. **The `feature-planning.md` workflow is the first test case** — it validates the runner against a real pipeline with existing test infrastructure.

**Epic 6 (Recovery):** `fam fix` becomes a workflow (`task-fix.md`) — the fix conversation is an analyst agent step, rollback is a tool call. Same execution environment.

**Epic 8 (CLI Management):** Scope reduced to CLI commands (`fam roles`, `fam skills`, `fam workflows`) and interactive session timeout/resume. File loading infrastructure is in Epic 4.5.

### Addendum Validation

**No new Elixir behaviours needed:** One generic `AgentProcess`, one implementation. Agent differentiation is in markdown.

**Backward compatibility:** Setting `max_parallel_agents = 1` reproduces sequential execution. Single-task `fam do` spawns a worker directly without a PM.

**Testing:** `AgentProcess` is tested once with scripted LLM responses (Mox). Different roles exercise different tool subsets but the same GenServer code. Role/skill file loading is tested with fixture files. The PM's orchestration behavior is tested by mocking the LLM to produce specific `spawn_agent` tool calls. The planning workflow migration (Epic 3r) validates the system end-to-end against existing test assertions.

**Safety:** Tool implementations enforce safety constraints regardless of what the role file instructs. A role file cannot escalate permissions. Safety enforcement operates at the tool layer, below the role/skill layer.

**The harness principle:** Familiar is a multi-agent harness. The Elixir code provides the execution environment, tools, and state systems. The markdown files define what agents do. This separation means: (1) users customize behavior without code, (2) new domains (not just coding) require only new markdown files, (3) the execution environment is testable independently of any specific workflow.

### Decision A5: Extension System & Lifecycle Hooks

**Decision:** The harness provides an extension API. Extensions are Elixir modules implementing `Familiar.Extension` behaviour. They register tools, supervision children, and lifecycle hook handlers. The Knowledge Store and Safety enforcement are default extensions, not hard-coded harness features.

**Extension behaviour:**

```elixir
defmodule Familiar.Extension do
  @type hook_registration :: %{
    hook: atom(),
    handler: module(),
    priority: integer(),  # lower = runs first (default 100)
    type: :alter | :event
  }

  @callback name() :: String.t()
  @callback tools() :: [{atom(), function(), String.t()}]
  @callback hooks() :: [hook_registration()]
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec() | nil
  @callback init(opts :: keyword()) :: :ok | {:error, term()}
end
```

**Two hook types:**

| Type | Mechanism | Use Case | Failure Mode |
|---|---|---|---|
| **Alter** | Synchronous pipeline (`Enum.reduce_while`) | `before_tool_call` — safety veto, arg modification | Skip broken handler, continue with unmodified value |
| **Event** | Async via `Familiar.Activity` PubSub | `on_agent_complete` — knowledge capture, logging | Process isolation — subscriber crash doesn't affect core |

**Alter hook pipeline:**

```elixir
# Core calls:
case Hooks.alter(:before_tool_call, %{tool: name, args: args}, %{agent: pid}) do
  {:ok, %{tool: name, args: possibly_modified_args}} -> execute_tool(name, args)
  {:halt, reason} -> {:error, {:tool_blocked, reason}}
end

# Pipeline runs handlers in priority order (lower first):
# Priority 1:  SafetyExtension.before_tool_call → validates paths, rejects dangerous ops
# Priority 50: AuditExtension.before_tool_call → logs the call
# Priority 100: CustomExtension.before_tool_call → custom checks
```

**Error isolation for alter hooks:**
- Each handler call wrapped in `Task.async` with 5-second timeout
- `try/rescue` catches exceptions — broken handler is skipped, value passes through unmodified
- Circuit breaker: 3 consecutive failures on same hook → handler disabled until extension reload
- Core never crashes because an extension misbehaved

**Event hooks via Activity PubSub:**
- The `Familiar.Hooks` module subscribes to Activity topics on behalf of extensions
- Extensions declare which events they care about via `hooks/0`
- PubSub process isolation means a crashing subscriber doesn't affect core or other subscribers
- No new mechanism needed — Activity is the unified event bus, hooks are organized subscribers

**MVP lifecycle hooks:**

| Hook | Type | Purpose |
|---|---|---|
| `before_tool_call` | alter | Safety enforcement, arg validation, audit logging |
| `after_tool_call` | event | Result logging, knowledge capture from tool outputs |
| `on_agent_complete` | event | Post-task knowledge hygiene, cleanup, notifications |
| `on_agent_error` | event | Error logging, failure analysis |
| `on_file_changed` | event | Knowledge store freshness (file watcher → KS update) |

**Post-MVP hooks** (added as extensions need them): `before_agent_start` (alter), `on_workflow_complete` (event), `on_message` (event), `on_init`/`on_shutdown` (events).

**Default extensions:**

| Extension | Tools | Hooks | Supervision |
|---|---|---|---|
| Knowledge Store | `search_context`, `store_context` | `after_tool_call`, `on_agent_complete`, `on_file_changed` | Embedding pool, file watcher |
| Safety | (none — operates via hooks only) | `before_tool_call` (priority 1) | None |

**Safety as an extension:**
Safety enforcement moves from being hard-coded in tool implementations to being a default extension with priority 1 on `before_tool_call`. The alter pipeline runs safety checks before any tool executes:
- Path validation (no traversal, project directory only)
- Git protection (no commits without approval)
- Delete constraints (own-task files only)
- Shell command restriction (configured allow-list)
- Secret detection (before knowledge storage)

Because safety is an extension: (1) users can add stricter rules, (2) users can customize for different domains, (3) the safety policy is inspectable and testable independently of tool implementations. Tools become thin — they just execute. Safety is a cross-cutting concern handled by the hook pipeline.

**Extension configuration (MVP):**
```elixir
# config/config.exs
config :familiar, :extensions, [
  Familiar.Extensions.Safety,
  Familiar.Extensions.KnowledgeStore
]
```

Extensions are loaded in `Application.start/2`. Their child specs are added to the supervision tree. Their tools are registered with the ToolRegistry. Their hooks are registered with the Hooks module. Post-MVP: extensions discoverable from hex packages with CLI management (`fam extensions list/add/remove`).

**Harness core (not extensions):**
- AgentProcess — generic executor
- ToolRegistry — tool discovery and dispatch
- WorkflowRunner — step sequencing
- Hooks — alter pipeline + event dispatch
- Activity — PubSub event broadcasting
- Conversations — runner-managed conversation state
- Providers — LLM abstraction
- Repo, PubSub — infrastructure

**The test:** if an agent directly invokes it as a tool call, it's an extension capability. If the runner manages it internally, it's harness core.
