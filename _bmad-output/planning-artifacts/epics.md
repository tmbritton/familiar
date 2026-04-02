---
stepsCompleted: [step-01, step-02, step-03, step-04]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
---

# Familiar - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Familiar, decomposing the requirements from the PRD, UX Design, and Architecture into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: User can initialize Familiar on an existing project directory, triggering automated project scanning
FR2: System can auto-detect installed LLM providers, available models, and project language
FR3: System can scan project files and classify them as index, skip, or ask based on configurable skip patterns
FR4: System can discover and report project conventions (naming patterns, package structure, error handling, template patterns) from indexed files
FR5: User can review and correct convention discovery results and file classifications
FR6: System can validate configured language commands (test, build, lint) during initialization
FR7: User can configure LLM providers, models, language settings, and scan preferences via project-local config
FR7b: Initialization is atomic — either completes fully or leaves no `.familiar/` directory. No partial state on failure
FR7c: Any `fam` command in a directory without `.familiar/` triggers initialization automatically
FR7d: Convention discovery reports evidence alongside conclusions (e.g., "snake_case files (61/64 files)")
FR8: System can create and maintain a semantic knowledge store containing navigational facts, decisions, gotchas, and relationships about the project
FR9: System can embed knowledge entries using a local embedding model for semantic search
FR10: System can retrieve relevant knowledge entries given a natural language query, ranked by semantic similarity
FR11: System validates context freshness on every task dispatch — entries referencing deleted files are excluded, entries referencing modified files are autonomously refreshed
FR12: System can store new knowledge discovered during task execution (facts, decisions, gotchas, relationships) via a post-task hygiene loop
FR13: User can search the knowledge store with natural language queries
FR14: User can inspect, edit, and delete individual knowledge store entries
FR15: User can trigger a full or partial project re-scan to reconcile the knowledge store — user-created and user-edited entries are preserved
FR16: User can consolidate redundant knowledge entries
FR17: User can snapshot the knowledge store and task tracker and restore — either fully or selectively to a specific point in time
FR18: System can report knowledge store health (entry count, retrieval performance, staleness ratio, last refresh)
FR19: System enforces knowledge-not-code rule — stores knowledge about code, never duplicates file contents
FR19b: System auto-backs up the knowledge store and task tracker after each successful batch execution
FR19c: System can auto-restore from backup on startup if database integrity check fails
FR20: User can describe a feature in natural language and initiate a planning conversation
FR21: System can query the knowledge store during planning to avoid asking questions it can answer from context
FR22: System can adapt planning conversation depth based on intent clarity
FR23: User can end the planning conversation at any point and have the system generate a spec with stated assumptions
FR24: System can generate a feature specification with claims verified against knowledge store and filesystem — verified claims marked, unverified assumptions flagged, and context sources cited
FR24b: System streams a reasoning trail to the terminal during planning — showing what it's checking, what it verified, and what it flagged
FR25: User can review and approve a generated spec in the browser (rendered LiveView with verification marks, knowledge links, approve/edit/reject keybindings) or via `--editor` flag in `$EDITOR`
FR26: System can decompose an approved spec into an epic with groups and ordered tasks with dependency mapping
FR27: User can review and approve the generated task list, requesting regrouping if needed
FR28: System can check for conflicts between new tasks and existing tasks in the tracker
FR29: When cross-plan conflicts are detected, system recommends resolution options and user selects approach
FR30: User can resume a suspended planning conversation
FR31: System validates plan freshness before task execution — warns if referenced files changed since plan creation
FR32: System persists a four-level work hierarchy (Epic → Group → Task → Subtask) with status, priority, and dependencies. Status rolls up: any failed subtask = task ❌, self-repaired = 🔧, all green = ✅
FR33: User can reorder task priority
FR34: User can remove tasks with warning about dependent tasks
FR35: User can view which tasks modified a specific file
FR36: System can archive completed epics and prompt for archival when all tasks complete
FR37: User can discard an entire epic plan, removing its spec and all associated groups/tasks
FR38: User can execute tasks — individually by ID, next by priority, next N in sequence, or all in dependency/priority order
FR39: System can execute multi-step workflows where each step's output is available to subsequent steps
FR40: System can run interactive workflow steps (multi-turn conversation) and autonomous steps (run to completion)
FR41: System can read actual project files from the filesystem at execution time
FR42: System can inject relevant knowledge into the agent prompt before execution
FR43: Workflow steps can customize agent behavior beyond the default role definition
FR44: User can cancel a running task with rollback of in-progress file changes
FR45: User can execute a task with a specific LLM provider override
FR46: System streams agent activity to the user in real time during task execution
FR47: System generates an execution summary after batch completion
FR48: System validates task output by running configured test, build, and lint commands, verifying task description elements, and checking for unnecessary duplication
FR49: System can retry a failed autonomous workflow step once before aborting
FR50: System can rollback file changes atomically when a task fails or is cancelled
FR51: System can restart a workflow from a failed step without replaying completed steps
FR52: System can handle cascading dependency failures — skip dependent tasks, continue executing independent tasks
FR53: System can detect LLM provider failure, retry with backoff, and pause execution after configurable threshold
FR54: System can report task failure within 30 seconds of detection with explanation and rollback status
FR55: System can track which files each task modified for downstream impact analysis
FR56: System detects interrupted task state on daemon startup and recovers — rolling back partial file changes
FR56b: In unattended execution, if a target file has been modified by the user since task start, system saves familiar's version as `.fam-pending`
FR57: User can initiate unified recovery at any hierarchy level — `fam fix #N` or Telescope picker. Fix opens with failure analyzed, ambiguity identified, options proposed
FR57b: System autonomously self-repairs where possible — refreshing stale context and retrying before involving the user
FR58: System enforces that agents can only read and write files within the project directory
FR59: System enforces that agents cannot commit to git without explicit user approval
FR60: System enforces that agents can only delete files created by the current task
FR61: System enforces that agents can only execute shell commands defined in the language configuration
FR62: System does not persist secrets, API keys, or credentials detected in code to the knowledge store
FR63: System skips vendor and dependency directories by default during scanning, enforced on all ingestion paths
FR64: System warns on first use of an external LLM provider per session and re-prompts after inactivity timeout
FR65: User can create, edit, and delete workflow definitions as markdown files
FR66: User can create, edit, and delete role definitions as markdown files
FR67: System validates workflow and role files on load, producing clear error messages for invalid files
FR68: System can suspend interactive workflow steps after idle timeout and allow user to resume later
FR69: User can add new language support by creating a configuration file without modifying system code
FR70: System supports thesis validation — executing tasks with different providers for comparison, with context injection disabled for ablation testing
FR71: Daemon serves a Phoenix LiveView web UI on a localhost port, auto-starting with the daemon
FR72: `fam plan` auto-opens the browser to the rendered spec review page on first spec generation per planning session
FR73: Spec review page renders markdown with inline verification marks (✓/⚠), convention annotations, and knowledge links
FR74: User can approve, edit, or reject a spec via keyboard shortcuts in the browser
FR75: Triage dashboard shows work hierarchy with worst-first sort, drill-down navigation, and live status updates
FR76: Search picker overlay (Telescope-style) is available from any view via `Space` keybinding
FR77: Web UI is fully keyboard-navigable with view shortcuts (s/t/w/l/?/Esc)
FR78: All CLI commands support `--json` output as a global flag — output format is an interface contract
FR79: System sends OS-native notifications for execution completion and pause events

### NonFunctional Requirements

NFR1: Context store retrieval completes in under 2 seconds on target hardware (Apple M1/M2 Pro, 16-32GB) with 200+ entries
NFR2: Local model inference (14B) produces first output tokens within 5 seconds on target hardware
NFR3: Init scan completes within 5 minutes for projects up to 200 source files
NFR4: Daemon remains responsive to read-only commands during task execution — read-only queries return within 1 second
NFR5: Web UI spec review page loads in under 1 second from `fam plan` completion to rendered spec in browser
NFR6: LiveView updates delivered within 100ms of server-side event
NFR7: Web UI search: text matches <50ms, semantic results stream within 200ms
NFR8: Web UI supports at least 1 concurrent browser session
NFR9: File operations are atomic — either complete fully or roll back. No partial writes survive a crash
NFR10: Context store and task tracker persist in crash-safe storage. Database integrity checked on startup with auto-restore
NFR11: Daemon detects interrupted state on restart and recovers without user intervention
NFR12: Auto-backup of context store and task tracker after each successful batch execution
NFR13: System runs for 8+ hours without memory leaks or degradation (memory ≤2x, retrieval ≤1.5x)
NFR14: Minimum project scale for stability: 100+ files, 5K+ lines, 200+ context entries
NFR15: Agent output must pass the project's configured linter/formatter
NFR16: Agent must generate tests for new functionality with behavioral assertions and error/edge case coverage
NFR17: Agent follows conventions discovered during init scan and injected via knowledge store
NFR18: System operates within model context window limits with prioritized context and truncation warnings
NFR19: Ollama provider: thin abstract interface, minimal code changes on API changes
NFR20: Anthropic provider: same thin interface
NFR21: Provider failure handled gracefully — retry with backoff, pause, resume, no silent data loss
NFR22: Every CLI command supports `--json` with consistent documented schema
NFR23: `--quiet` mode outputs minimal text suitable for scripting on all commands
NFR24: Output schemas documented and treated as interface contract — breaking changes versioned
NFR25: Triage tier definitions: ✅ complete (no retries after failure), 🔧 self-repaired (retry after failure), ⊘ blocked (dependency wait), ❌ needs input (failed after all retries)
NFR26: Codebase understandable and modifiable by a single developer
NFR27: Dependencies minimized — standard Elixir/OTP, SQLite, Phoenix LiveView
NFR28: Configuration is data (TOML, markdown), not code — adding languages/roles/workflows requires no Elixir knowledge
NFR29: Test suite exists for core functionality — the system that validates agent code must itself be validated
NFR30: Default-skip untrusted sources (vendor, node_modules, dependencies) enforced on all ingestion paths
NFR31: Structural prompt isolation — injected context in delineated data section
NFR32: Knowledge-not-code rule enforced — never store interpretive observations without evidence
NFR33: Spec claims verified with freshness check — context-influenced questions cite sources
NFR34: Per-session frontier warning — first external API call prompts confirmation, re-prompts after inactivity

### Additional Requirements

- Architecture specifies starter template: `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard` — first implementation story
- Post-generation modifications: strip Tailwind, strip default layout, add sqlite_vec, add req, configure daemon architecture, add CLI entry point, replace license with AGPL-3.0, configure `.familiar/` directory structure
- Hexagonal architecture with 6 Mox-based behaviour ports: LLM Provider, FileSystem, Embedder, Shell, Notifications, Clock
- 100% test coverage enforced on 6 critical modules: TaskStateMachine, TransactionLog, PromptAssembly, Verification, ValidationPipeline, DependencyResolver
- Property-based testing with StreamData for the 6 critical modules
- Context boundary enforcement via `boundary` hex package
- 7 public API facade modules with documented function signatures
- Domain-driven Ecto contexts: knowledge/, work/, planning/, execution/, files/, providers/, cli/
- CLI as HTTP client of daemon — never imports from business domain contexts directly
- Hybrid CLI-daemon communication: HTTP (req) for simple commands, Phoenix Channel (WebSocket) for interactive commands
- Per-project daemon with dynamic port stored in `.familiar/daemon.json`
- Auto-start daemon on first `fam` command; auto-shutdown via `fam daemon stop`
- Crash recovery sequence: database integrity check → file transaction rollback → orphaned task reconciliation
- Version handshake between CLI and daemon
- Init runs in-process (no daemon) with blocking embedding — all embeddings complete before init reports success
- sqlite-vec integration spike needed early to de-risk thesis-critical retrieval path
- Knowledge extraction spike needed early to validate "index card system" approach
- Error handling convention: `{:ok, result}` or `{:error, {atom_type, map_details}}` with `recoverable?/1` policy function
- Config: TOML for project config, YAML frontmatter for role/workflow markdown
- PubSub convention: topics `"familiar:{context}:{entity}"`, past-tense atom events
- Streaming normalization: provider adapters translate to common format ({:text_delta, ...}, {:tool_call_delta, ...}, {:done, ...})
- Agent runner safety limits: max tool calls per task (~100), task timeout, intended files list with warnings, full LLM response logging
- Agent runner tool call loop: send prompt → receive response → parse tool calls → execute → append results → repeat
- Prompt assembly as pure function returning `{prompt, metadata}` — thesis-critical transformation
- Planning conversation persistence in SQLite `planning_messages` table
- Verification derived from tool call log — LLM cannot self-report verification status
- Convention injection: semantic retrieval only for MVP, measured upgrade path to two-source injection
- File transaction module: strict write sequence (log intent → write file → log completion), pre-write stat check, idempotent rollback
- Secret detection: regex-based scan before storing knowledge entries
- Foundational implementation: test scaffold (6 Mox mocks, StreamData generators, test factories, ExUnit case templates), context boundaries (7 public API facades), daemon lifecycle, config loading, sqlite-vec spike, knowledge extraction spike

### UX Design Requirements

UX-DR1: Custom minimal CSS design system with CSS custom properties as design tokens — browser reset + hand-written styles, no framework, no component library
UX-DR2: Terminal-adjacent dark minimal visual direction — monospace where appropriate, dark background, high-contrast text, color only for meaning
UX-DR3: Semantic color palette with three categories (green/amber/red) carrying aligned meanings: triage states, context health, knowledge state, verification status
UX-DR4: Dual-density typography model — tool density (~0.8-0.85rem, line-height ~1.3) for dashboards/lists, reading density (~0.95rem, line-height ~1.5-1.6) for spec prose and documentation
UX-DR5: Two font stacks with no bundled fonts — monospace for tool elements, system-ui sans-serif for reading prose
UX-DR6: Five-step spacing scale (xs through xl) with tool views at half typical web spacing, reading views at comfortable spacing
UX-DR7: Accessibility requirements: primary text ≥7:1 contrast (AAA), muted text ≥4.5:1 (AA), visible focus indicators, `role="status"` on status bar, `role="dialog"` on picker, aria-labels on verification marks
UX-DR8: Status bar component — persistent bottom bar across all views showing context-specific keybindings, `role="status"` with live region
UX-DR9: Search picker component (Telescope-style) — split pane overlay with results + preview, two-phase rendering (instant text <50ms, streaming semantic <200ms), linked preview with Tab navigation, available via `Space` from any view
UX-DR10: Triage list component — grouped worst-first list with j/k navigation, Enter to drill, feature-level grouping, live status updates
UX-DR11: Spec renderer component — rendered markdown with inline verification marks (✓ green / ⚠ amber), convention annotations in muted italic, knowledge links with dotted underline on focus, metadata line with trust summary
UX-DR12: Work hierarchy component — depth indicator header, Enter to drill down, Esc to back up, flexible depth (empty levels collapse)
UX-DR13: Activity feed component (Watch view) — streaming structured output showing current task activity, subtask progress checklist, completed tasks below, tool density, real-time via PubSub
UX-DR14: Knowledge browser component (Library view) — browsable entries with type badges, inline search, type filter tabs, entry preview with linked artifacts
UX-DR15: Help overlay component — single-screen keybinding reference organized by view context, monospace tool density
UX-DR16: Two-layer notification system — global status indicator (conditional line above status bar, persists until state resolves) + ephemeral toast messages (auto-dismissing, max 3 stacked)
UX-DR17: Empty states for all views with one-sentence explanation + one-sentence next action
UX-DR18: Execution sanity check — `fam do --all` shows brief status line of what's about to execute (not a confirmation prompt)
UX-DR19: Destructive action confirmation only for `fam restore` — all other actions execute immediately with toast confirmation
UX-DR20: System error communication with four severity levels: recoverable (auto-retry), blocking (global status), degraded (global status), fatal (full-screen with recovery command)
UX-DR21: Vim-style navigation within views: j/k to move, Enter to select/expand, view-specific actions shown in status bar
UX-DR22: Zero-chrome web UI — no sidebar, no top nav, no breadcrumbs. Content and a thin status bar only. Strip all default Phoenix layout elements
UX-DR23: All keybindings remappable and colors configurable via `.familiar/config.toml`
UX-DR24: Progressive onboarding — guided first-run, first-plan orientation, progressive hints that fade after ~5 sessions
UX-DR25: CLI output legible at 80 columns minimum, optimized for 120 columns, works in half-screen terminal pane and narrow tmux splits
UX-DR26: Streaming reasoning trail in terminal — one line per conclusion (~10-20 lines per spec), heartbeat if no output for 5+ seconds, progressive hint on first use
UX-DR27: `fam watch` as structured real-time activity display in terminal — formatted as live-updating status, works in narrow tmux split

### FR Coverage Map

FR1: Epic 1 — Initialize Familiar on existing project
FR2: Epic 1 — Auto-detect providers, models, language
FR3: Epic 1 — Scan and classify project files
FR4: Epic 1 — Discover project conventions
FR5: Epic 1 — Review/correct conventions and classifications
FR6: Epic 1 — Validate language commands during init
FR7: Epic 1 — Configure providers, models, language, scan preferences
FR7b: Epic 1 — Atomic initialization
FR7c: Epic 1 — Auto-trigger init on any fam command
FR7d: Epic 1 — Convention evidence reporting
FR8: Epic 2 — Create/maintain semantic knowledge store
FR9: Epic 2 — Embed knowledge entries for semantic search
FR10: Epic 2 — Retrieve entries by semantic similarity
FR11: Epic 2 — Validate context freshness on dispatch
FR12: Epic 2 — Post-task knowledge capture via hygiene loop
FR13: Epic 2 — User search with natural language queries
FR14: Epic 2 — Inspect, edit, delete knowledge entries
FR15: Epic 2 — Full/partial project re-scan
FR16: Epic 2 — Consolidate redundant entries
FR17: Epic 2 — Snapshot and restore knowledge store
FR18: Epic 2 — Knowledge store health reporting
FR19: Epic 2 — Knowledge-not-code rule enforcement
FR19b: Epic 2 — Auto-backup after batch execution
FR19c: Epic 2 — Auto-restore from backup on corruption
FR20: Epic 3 — Initiate planning conversation
FR21: Epic 3 — Query knowledge store during planning
FR22: Epic 3 — Adaptive planning depth
FR23: Epic 3 — End conversation and generate spec with assumptions
FR24: Epic 3 — Generate verified spec with cited sources
FR24b: Epic 3 — Streaming reasoning trail
FR25: Epic 3 — Browser spec review with verification marks
FR26: Epic 3 — Decompose spec into epic/groups/tasks
FR27: Epic 3 — Review and approve task list
FR28: Epic 3 — Cross-plan conflict detection
FR29: Epic 3 — Conflict resolution recommendations
FR30: Epic 3 — Resume suspended planning conversation
FR31: Epic 3 — Plan freshness validation
FR32: Epic 4 — Four-level work hierarchy with state machine
FR33: Epic 4 — Reorder task priority
FR34: Epic 4 — Remove tasks with dependency warnings
FR35: Epic 4 — View file modification history per task
FR36: Epic 4 — Archive completed epics
FR37: Epic 4 — Discard entire epic plan
FR38: Epic 5 — Execute tasks (individual, batch, all)
FR39: Epic 5 — Multi-step workflow execution
FR40: Epic 5 — Interactive and autonomous workflow steps
FR41: Epic 5 — Read project files at execution time
FR42: Epic 5 — Inject knowledge into agent prompt
FR43: Epic 5 — Step-specific agent behavior customization
FR44: Epic 5 — Cancel task with rollback
FR45: Epic 5 — Provider override per task
FR46: Epic 5 — Stream agent activity in real time
FR47: Epic 5 — Execution summary after batch completion
FR48: Epic 5 — Validate output (test/build/lint/coverage/duplicate)
FR49: Epic 5 — Retry failed step once before abort
FR50: Epic 5 — Atomic rollback on failure/cancel
FR51: Epic 5 — Restart workflow from failed step
FR52: Epic 5 — Cascading dependency failure handling
FR53: Epic 5 — Provider failure detection with retry/pause/resume
FR54: Epic 5 — Report failure within 30 seconds
FR55: Epic 5 — Track file modifications per task
FR56: Epic 5 — Interrupted state detection and recovery on startup
FR56b: Epic 5 — Unattended file conflict → .fam-pending
FR57: Epic 6 — Unified recovery at any hierarchy level (fam fix)
FR57b: Epic 6 — Autonomous self-repair before user involvement
FR58: Epic 5 — Project directory sandboxing
FR59: Epic 5 — Git commit protection
FR60: Epic 5 — Deletion constraint (current task files only)
FR61: Epic 5 — Shell command restriction to language config
FR62: Epic 2 — Secret filtering from knowledge store
FR63: Epic 1 — Vendor/dependency skip enforcement
FR64: Epic 5 — Frontier provider per-session warning
FR65: Epic 8 — Create/edit/delete workflow definitions
FR66: Epic 8 — Create/edit/delete role definitions
FR67: Epic 8 — Validate workflow/role files on load
FR68: Epic 8 — Suspend/resume interactive workflow steps
FR69: Epic 8 — Add language support via config file
FR70: Epic 5 — Thesis validation (provider comparison, ablation)
FR71: Epic 7 — LiveView web UI auto-starting with daemon
FR72: Epic 7 — Auto-open browser to spec review
FR73: Epic 7 — Spec review with verification marks
FR74: Epic 7 — Keyboard approve/edit/reject in browser
FR75: Epic 7 — Triage dashboard with worst-first sort
FR76: Epic 7 — Telescope-style search picker overlay
FR77: Epic 7 — Full keyboard navigation with view shortcuts
FR78: Epic 1 — --json output as global flag (cross-cutting, day one)
FR79: Epic 7 — OS-native notifications

## Epic List

### Epic 1: Project Foundation & Initialization
User can install Familiar, initialize it on their project, and see it learn their codebase conventions. The daemon starts, providers are detected, files are scanned, and conventions are discovered with evidence — the first proof that the familiar "gets" the project.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR7b, FR7c, FR7d, FR63, FR78
**Includes:** Phoenix project setup (starter template), daemon lifecycle, provider behaviour + adapters, hexagonal port definitions, Ecto schemas + migrations, sqlite-vec spike, knowledge extraction spike, CLI entry point, --json from day one, error handling conventions, config loading (TOML + YAML frontmatter), test scaffold (6 Mox mocks, factories, case templates)

## Epic 1: Project Foundation & Initialization

User can install Familiar, initialize it on their project, and see it learn their codebase conventions. The daemon starts, providers are detected, files are scanned, and conventions are discovered with evidence — the first proof that the familiar "gets" the project.

### Story 1.1a: Phoenix Project Setup & Database Foundation

As a developer,
I want a properly configured Phoenix project with SQLite and sqlite-vec working,
So that all subsequent stories build on a solid, compilable foundation.

**Acceptance Criteria:**

**Given** no project exists yet
**When** the developer runs `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard` and applies post-generation modifications
**Then** the project compiles with zero warnings
**And** Tailwind CSS and default Phoenix layout are stripped
**And** all dependencies are added: sqlite_vec, req, mox, stream_data, boundary, toml, yaml_elixir
**And** license is AGPL-3.0
**And** `.formatter.exs` and `.credo.exs` are configured
**And** `mix format` and `mix credo --strict` pass

**Given** the project is set up
**When** the Ecto Repo starts
**Then** SQLite3 database is created and sqlite-vec extension loads successfully
**And** vector column operations (insert, similarity query) work correctly
**And** `mix test` passes with Ecto sandbox properly configured

### Story 1.1b: Behaviour Ports, Domain Contexts & Test Scaffold

As a developer,
I want hexagonal architecture ports, domain-driven contexts, and test infrastructure in place,
So that all business logic is testable through behaviour mocks and context boundaries are enforced.

**Acceptance Criteria:**

**Given** the Phoenix project exists (from 1.1a)
**When** the 6 behaviour ports are defined (LLM, FileSystem, Embedder, Shell, Notifications, Clock)
**Then** each behaviour has a defined callback specification
**And** Mox mock definitions exist for all 6 behaviours in test config
**And** ExUnit case templates for sandbox and mock setups are available
**And** test factories for knowledge entries, tasks, and specs are created
**And** test coverage reporting is enabled with mid-high 90s% CI threshold

**Given** the project uses domain-driven contexts
**When** the directory structure is created (knowledge/, work/, planning/, execution/, files/, providers/, cli/)
**Then** each context has a public API facade module (e.g., `Familiar.Knowledge`, `Familiar.Work`)
**And** `boundary` package is configured to enforce context boundaries at compile time
**And** the error module with `recoverable?/1` policy function exists
**And** public API facade modules are stubs with function specs and `@moduledoc` — business logic is implemented in their respective epics, not here

**Given** all infrastructure is in place
**When** `mix test` is run
**Then** all tests pass with Ecto sandbox and Mox mocks properly configured
**And** `mix compile --warnings-as-errors` passes
**And** `boundary` compile-time checks pass

### Story 1.2: Provider Adapters & Embedding Pipeline

As a developer,
I want Familiar to connect to Ollama for LLM inference and embedding generation,
So that the system can extract knowledge from code and store it as searchable vectors.

**Acceptance Criteria:**

**Given** Ollama is running with an embedding model and a coding model
**When** the Ollama LLM adapter is called with a chat prompt
**Then** it returns a response through the `Familiar.Providers.LLM` behaviour
**And** streaming responses are normalized to common event format ({:text_delta, ...}, {:tool_call_delta, ...}, {:done, ...})

**Given** Ollama is running with an embedding model
**When** the Ollama embedder adapter is called with text
**Then** it returns a vector through the `Familiar.Knowledge.Embedder` behaviour
**And** the vector can be stored in a sqlite-vec column
**And** similarity queries return entries ranked by cosine distance

**Given** the system starts up
**When** provider auto-detection runs
**Then** the system detects whether Ollama is running at localhost:11434
**And** reports available models (embedding + coding)
**And** returns clear error if Ollama is unavailable

**Given** the embedding pipeline is complete
**When** a knowledge entry is created with text content
**Then** the text is embedded via Ollama and stored with its vector
**And** the entry is retrievable by semantic similarity query
**And** retrieval completes within 2 seconds for 200+ entries (NFR1)

**Given** provider adapters are tested
**When** unit tests run with Mox mocks
**Then** all adapter behaviour callbacks are covered
**And** streaming normalization is tested with scripted responses

### Story 1.3a: Daemon Lifecycle

As a user,
I want the Familiar daemon to run as a background process with health monitoring and crash recovery,
So that the system is always available and recovers gracefully from failures.

**Acceptance Criteria:**

**Given** no daemon is running for the current project
**When** the daemon is started
**Then** a Phoenix application starts as a background process
**And** a dynamic port is written to `.familiar/daemon.json`
**And** a PID file is written to `.familiar/daemon.pid` with advisory lock
**And** the health endpoint responds at `GET /api/health` with `{status: "ok", version: "x.y.z"}`

**Given** the daemon is running
**When** `fam daemon stop` is issued
**Then** the daemon shuts down gracefully and writes a clean shutdown marker
**And** `.familiar/daemon.json` is cleaned up

**Given** the daemon was killed without clean shutdown (power loss, OOM)
**When** the daemon restarts
**Then** crash recovery runs: database integrity check → file transaction rollback → orphaned task reconciliation
**And** absence of clean shutdown marker triggers recovery sequence

**Given** daemon lifecycle is implemented
**When** unit tests run
**Then** health endpoint, PID file management, and crash recovery sequence are tested
**And** near-100% coverage on daemon lifecycle module

### Story 1.3b: CLI Entry Point & JSON Output

As a user,
I want a `fam` CLI that auto-starts the daemon and supports structured JSON output,
So that I never manually manage processes and can integrate with other tools.

**Acceptance Criteria:**

**Given** no daemon is running
**When** the user runs any `fam` command
**Then** the CLI auto-starts the daemon, waits for health check, then executes the command

**Given** a daemon is already running
**When** the user runs a `fam` command
**Then** the CLI reads `.familiar/daemon.json` and connects to the existing daemon
**And** a version handshake confirms CLI and daemon compatibility
**And** major version mismatch produces a clear warning with `fam daemon restart` instruction

**Given** the CLI entry point handles init mode
**When** no `.familiar/` directory exists
**Then** the CLI runs init in-process (no daemon) with a minimal supervision tree
**And** after init completes, the daemon starts as a background process

**Given** any command is run
**When** the `--json` flag is provided
**Then** output follows a consistent JSON envelope: `{"data": ...}` for success, `{"error": {"type": "...", "message": "...", "details": {...}}}` for errors (FR78)
**And** `--quiet` mode outputs minimal text suitable for scripting

**Given** CLI entry point is implemented
**When** unit tests run
**Then** auto-start, version handshake, init-mode branching, and JSON formatting are tested
**And** near-100% coverage on CLI entry point module

### Story 1.4: Project Initialization & File Scanning

As a user,
I want to initialize Familiar on my existing project so it scans and understands my codebase,
So that subsequent planning and execution have rich project context from day one.

**Acceptance Criteria:**

**Given** a project directory without `.familiar/`
**When** `fam init` is run (or any `fam` command triggers auto-init)
**Then** prerequisite checks run: Ollama running, embedding model available, coding model available
**And** the system scans all project files and classifies each as index, skip, or ask
**And** vendor/dependency directories are skipped by default (.git/, vendor/, node_modules/, _build/, deps/, etc.) per FR63
**And** progress is reported: "Scanning files... Discovering conventions... Building knowledge store (embedding N/M entries)..."

**Given** files are classified and scanned
**When** knowledge extraction runs on indexed files
**Then** natural language knowledge entries are created (file summaries, conventions, patterns, relationships, decisions)
**And** entries follow the knowledge-not-code rule — prose descriptions, not raw code
**And** all entries are embedded via Ollama before init reports success (blocking embedding)

**Given** init is in progress
**When** the user presses Ctrl+C at any point
**Then** the `.familiar/` directory is deleted entirely — no partial state (FR7b)

**Given** init completes successfully
**When** the user checks the knowledge store
**Then** all indexed files have corresponding knowledge entries with embeddings
**And** init completed within 5 minutes for projects up to 200 source files (NFR3)
**And** default MVP workflow files (feature-planning, feature-implementation, task-fix) and role files (analyst, coder, reviewer) are installed in `.familiar/workflows/` and `.familiar/roles/`
**And** on successful completion, a summary is displayed: files indexed, conventions stored, and a first-use hint ("Try: `fam plan "describe a feature"` — your spec will appear for review")

**Given** a project with no indexable source files (only config/generated)
**When** init completes
**Then** a warning is shown: "No source files found to index — Familiar will have limited context"
**And** init still succeeds with an empty knowledge store

**Given** the init scanner encounters a large project (500+ files)
**When** the file count exceeds the init budget
**Then** the system prioritizes source files over config/generated files
**And** extracts the top ~200 files by significance
**And** reports what was deferred

### Story 1.5: Convention Discovery & User Review

As a user,
I want Familiar to discover my project's conventions and show me the evidence,
So that I can verify the system understands my patterns and correct any misclassifications.

**Acceptance Criteria:**

**Given** the init scan has indexed project files
**When** convention discovery runs
**Then** the system identifies naming patterns, package structure, error handling, template patterns, and other conventions
**And** each convention includes evidence counts (e.g., "snake_case files (61/64 files)") per FR7d
**And** conventions are stored as knowledge entries of type "convention"

**Given** conventions are discovered
**When** the user is prompted to review
**Then** discovered conventions are displayed with evidence
**And** the user can accept all, edit individual conventions, or correct misclassifications (FR5)

**Given** the project has language-specific commands
**When** validation runs during init
**Then** configured test, build, and lint commands are validated (FR6)
**And** commands that fail produce clear error messages with instructions to fix

**Given** convention discovery completes
**When** unit tests run
**Then** convention extraction logic is covered with test cases for multiple project structures
**And** evidence counting is verified to be accurate

### Story 1.6: Configuration & Auto-Init

As a user,
I want project-local configuration in a simple TOML file and automatic initialization on first use,
So that setup is effortless and preferences persist across sessions.

**Acceptance Criteria:**

**Given** init has completed
**When** the user checks `.familiar/config.toml`
**Then** it contains default configuration for: provider settings, language config, scan preferences, notification preferences
**And** default language configurations exist for Go and Elixir

**Given** a directory without `.familiar/`
**When** the user runs any `fam` command (not just `fam init`)
**Then** initialization is triggered automatically (FR7c)
**And** after init completes, the original command is executed

**Given** the user edits config.toml with invalid values
**When** the config is loaded
**Then** validation produces `{:error, {:invalid_config, %{field: ..., reason: ...}}}` with specific field and reason
**And** the daemon does not crash — it reports the error and uses defaults where possible

**Given** the `--json` flag is used on any CLI command
**When** the command executes
**Then** output follows a consistent JSON envelope: `{"data": ...}` for success, `{"error": {"type": "...", "message": "...", "details": {...}}}` for errors (FR78)
**And** `--quiet` mode outputs minimal text suitable for scripting

**Given** configuration and auto-init are implemented
**When** unit tests run
**Then** TOML parsing, validation, and default generation are covered
**And** auto-init trigger logic is tested

### Story 1.7: Foundation Integration Test

As a developer,
I want an integration test that validates the full init pipeline end-to-end,
So that I can prove the foundational infrastructure works as a coherent system.

**Acceptance Criteria:**

**Given** the full foundation is built (SQLite + sqlite-vec, provider adapters, file system, knowledge store)
**When** the integration test runs
**Then** the golden path is validated: scan project files → classify (index/skip) → extract knowledge via mocked LLM → embed via mocked Ollama → store in real SQLite with sqlite-vec → retrieve by semantic similarity
**And** the test uses real SQLite via Ecto sandbox (not mocked) and sqlite-vec vector operations
**And** external systems (Ollama) are mocked via Mox with scripted responses
**And** the full pipeline completes without error and retrieval returns relevant entries
**And** the integration test runs against a project fixture with 100+ files to validate minimum scale (NFR14)

**Given** failure scenarios are tested
**When** the integration test exercises error paths
**Then** Ctrl+C during init leaves no `.familiar/` directory (atomic rollback)
**And** Ollama unavailable during init produces a clear error and clean exit
**And** corrupt/invalid files are skipped gracefully without halting the pipeline

---

**Epic 1 Summary:** 9 stories (1.1a, 1.1b, 1.2, 1.3a, 1.3b, 1.4, 1.5, 1.6, 1.7), covering FR1-FR7d, FR63, FR78 plus all foundational infrastructure. All 12 FRs addressed.

## Epic 2: Knowledge Store & Context Management

User can search, browse, inspect, edit, and manage the project knowledge Familiar has learned — with freshness validation, health monitoring, backup, and restore. The knowledge store autonomously maintains itself through post-task hygiene.

**Note:** All CLI commands in this epic support `--json` and `--quiet` per FR78 (established in Epic 1). Not repeated in individual story ACs.

### Story 2.1: Knowledge Entry CRUD & Semantic Search

As a user,
I want to search the knowledge store with natural language queries and get semantically relevant results,
So that I can find project context without knowing exact terms or file locations.

**Acceptance Criteria:**

**Given** knowledge entries exist in the store (created during init or manually)
**When** the user runs `fam search "how does authentication work"`
**Then** entries are returned ranked by semantic similarity to the query
**And** retrieval completes within 2 seconds for 200+ entries (NFR1)
**And** results include entry type, summary, source, and freshness status

**Given** the knowledge store public API (`Familiar.Knowledge`)
**When** `search/1`, `fetch_entry/1`, `store/1` are called
**Then** `search/1` returns a ranked list of entries
**And** `fetch_entry/1` returns `{:ok, entry}` or `{:error, {:not_found, details}}`
**And** `store/1` validates the knowledge-not-code rule (FR19) — rejects raw code, accepts prose descriptions
**And** entries are automatically embedded on creation (FR9)

**Given** the system creates knowledge entries
**When** any entry is stored via any path (init scan, hygiene loop, manual)
**Then** the entry contains: text content, embedding vector, type (fact/decision/gotcha/convention/relationship), source (init-scan/agent/user/decision), source file references, and timestamps (FR8)
**And** the knowledge-not-code rule is enforced — entries are navigational knowledge, not code copies (FR19)

**Given** search and CRUD operations are implemented
**When** unit tests run
**Then** semantic search ranking is tested with known embeddings (Mox mock for deterministic vectors)
**And** knowledge-not-code validation is tested with positive and negative cases
**And** all public API functions have near-100% coverage

### Story 2.2: Context Freshness Validation

As a user,
I want the knowledge store to automatically detect stale entries and refresh them,
So that I never get outdated context injected into my tasks.

**Acceptance Criteria:**

**Given** knowledge entries reference specific source files
**When** a task dispatch triggers freshness validation (FR11)
**Then** referenced files are stat-checked against the filesystem
**And** entries referencing deleted files are excluded from retrieval results
**And** entries referencing modified files are autonomously refreshed (re-extracted and re-embedded, not just flagged)
**And** freshness validation completes within the <2s retrieval budget

**Given** freshness validation is a synchronous gate on the critical path
**When** multiple files need stat-checking
**Then** file stats are batched and parallelized where possible
**And** the system fails-open with warnings rather than blocking indefinitely

**Given** freshness validation runs
**When** unit tests execute
**Then** the FileSystem behaviour mock provides controlled file stat responses
**And** all paths are tested: file unchanged, file modified, file deleted
**And** Clock mock controls time-based freshness logic
**And** if freshness validation fails to run (timeout, error, misconfiguration), the system logs a warning: "Context freshness validation skipped — results may include stale entries" visible in `fam status` and execution logs
**And** near-100% coverage on freshness validation module

### Story 2.3: Post-Task Hygiene Loop

As a user,
I want the system to automatically capture new knowledge after each task completes,
So that the knowledge store grows smarter with every task without manual intervention.

**Acceptance Criteria:**

**Given** a task has completed successfully (or succeeded after retry)
**When** the post-task hygiene loop runs (FR12)
**Then** new knowledge is extracted: facts discovered, decisions made, gotchas encountered, relationships found
**And** domain knowledge is captured from the SUCCESSFUL execution only (not failed attempts)
**And** failure gotchas are captured from the FAILURE REASON (not failed code)
**And** entries referencing the same source file as new discoveries are compared — if the new entry supersedes the old (same topic, newer source), the old is replaced
**And** new entries are embedded asynchronously via the embedding worker pool

**Given** the hygiene loop processes results
**When** it encounters knowledge that already exists in the store
**Then** it updates existing entries rather than creating duplicates

**Given** hygiene loop is implemented
**When** unit tests run
**Then** knowledge extraction from success vs failure scenarios is tested
**And** duplicate detection and update logic is covered
**And** near-100% coverage on hygiene module

### Story 2.4: Knowledge Store Management

As a user,
I want to inspect, edit, delete, and re-scan knowledge entries,
So that I can curate the knowledge store and fix incorrect information.

**Acceptance Criteria:**

**Given** knowledge entries exist in the store
**When** the user runs `fam search` and selects an entry
**Then** the full entry is displayed: content, type, source, freshness status, referenced files, creation date (FR14)
**And** the user can edit the entry content (entry is re-embedded after edit)
**And** the user can delete the entry
**And** user-created and user-edited entries are tagged with source type "user"

**Given** the user wants to refresh the knowledge store
**When** `fam context --refresh [path]` is run (FR15)
**Then** the system re-scans the specified path (or full project if no path)
**And** user-created and user-edited entries are preserved — only auto-generated entries are updated
**And** new files are indexed, deleted files' entries are removed

**Given** the user wants to consolidate redundant entries
**When** `fam context --compact` is run (FR16)
**Then** semantically similar entries are identified and presented for consolidation
**And** the user confirms which entries to merge
**And** merged entries retain the most complete information

**Given** management operations are implemented
**When** unit tests run
**Then** edit-and-re-embed, delete, re-scan with user entry preservation, and consolidation are all tested
**And** near-100% coverage on management functions

### Story 2.5: Backup, Restore & Health Monitoring

As a user,
I want automatic backups, easy restore, and health visibility for the knowledge store,
So that I never lose accumulated knowledge and can quickly assess system state.

**Acceptance Criteria:**

**Given** a batch execution completes successfully
**When** the post-batch hook fires
**Then** the knowledge store and task tracker are automatically backed up (FR19b)
**And** backups are stored in `.familiar/backups/` with timestamps

**Given** the user wants to manually backup or restore
**When** `fam backup` is run
**Then** a snapshot of the knowledge store and task tracker is created (FR17)
**When** `fam restore` is run
**Then** available snapshots are listed and the user selects one to restore
**And** `fam restore` is the ONLY command requiring confirmation before execution (UX-DR19) — all other actions (approve, reject, delete, fix, execute) run immediately with toast confirmation
**And** restore can be full or selective to a specific point in time

**Given** the daemon starts and detects database corruption
**When** integrity check fails
**Then** the system auto-restores from the most recent backup (FR19c)
**And** the user sees "Database restored from backup (date). Verify with `fam status`"

**Given** the user checks knowledge store health
**When** `fam status` or `fam context --health` is run (FR18)
**Then** the output shows: entry count, retrieval performance, staleness ratio, last refresh, backup status
**And** health is summarized as green/amber/red signal

**Given** backup and health are implemented
**When** unit tests run
**Then** backup creation, restore flow, auto-restore on corruption, and health reporting are all tested
**And** near-100% coverage on backup and health modules

### Story 2.6: Secret Filtering

As a user,
I want the system to automatically strip secrets from knowledge entries before storage,
So that API keys, credentials, and tokens are never persisted in the knowledge store.

**Acceptance Criteria:**

**Given** any knowledge entry is about to be stored (from init scan, hygiene loop, or manual creation)
**When** the entry text is scanned for secret patterns (FR62)
**Then** regex patterns detect: API key formats (sk_live_*, AKIA*, ghp_*), base64 tokens >40 chars, URLs with embedded credentials, environment variable names (DATABASE_URL, SECRET_KEY, API_KEY)
**And** detected secret VALUES are stripped — the REFERENCE is stored (e.g., "Stripe API key configured in .env")
**And** the original secret value is never written to the database

**Given** secret filtering is implemented
**When** unit tests run
**Then** each secret pattern type is tested with positive matches and negative (safe) cases
**And** the stripping logic is verified to preserve references while removing values
**And** near-100% coverage on secret filtering module

---

### Story 2.7: Knowledge Store Integration Test

As a developer,
I want an integration test that validates the full knowledge store lifecycle,
So that I can prove search, freshness, hygiene, and backup/restore work as a coherent system.

**Acceptance Criteria:**

**Given** the knowledge store integration test runs
**When** the golden path executes
**Then** the full lifecycle is validated: store entry with embedding → search by semantic similarity → freshness check against filesystem (file modified → auto-refresh) → hygiene loop captures new knowledge from task completion → backup snapshot → restore from backup
**And** real SQLite via Ecto sandbox with sqlite-vec for vector operations
**And** FileSystem behaviour mocked for controlled file stat responses
**And** Embedder behaviour mocked with deterministic vectors

**Given** failure scenarios are tested
**When** the integration test exercises error paths
**Then** secret filtering blocks entries containing API key patterns
**And** knowledge-not-code rule rejects raw code content
**And** auto-restore triggers when database integrity check fails
**And** freshness validation excludes entries referencing deleted files

**Epic 2 Summary:** 7 stories, covering FR8-FR19c and FR62. All 15 FRs addressed.

## Epic 3: Planning & Specification

User can plan features through context-aware conversations that query the knowledge store, adapt depth to intent clarity, and produce verified specs with cited sources. Specs are reviewed in the browser or editor, then decomposed into task hierarchies with dependency mapping.

### Story 3.1: Planning Conversation Engine

As a user,
I want to describe a feature in natural language and have a context-aware conversation that sharpens my intent,
So that the system understands what I want to build without me manually providing context.

**Acceptance Criteria:**

**Given** the user runs `fam plan "add user accounts"`
**When** the planning conversation starts (FR20)
**Then** the system queries the knowledge store for relevant context before asking any question (FR21)
**And** the system never asks a question it can answer from existing context
**And** the conversation adapts depth to intent clarity (FR22) — intent clarity is estimated by the LLM from the initial prompt: short/vague prompts trigger more questions (3-5), detailed prompts with specific file references trigger fewer (0-2). This is prompt-instructed behaviour, not a separate classifier

**Given** a planning conversation is in progress
**When** the system asks clarifying questions
**Then** questions are novel — they surface edge cases, ambiguities, or unresolved decisions
**And** repeat questions are treated as a system failure
**And** context-influenced questions cite their source ("Based on your repository pattern in db/...")

**Given** a planning conversation is in progress
**When** the user leaves and returns later
**Then** `fam plan --resume` resumes the conversation from where it left off (FR30)
**And** message history is loaded from the `planning_messages` SQLite table (session_id, role, content, tool_calls, timestamp)
**And** the system does not re-ask previously answered questions

**Given** the planning engine communicates interactively
**When** `fam plan` is invoked
**Then** the conversation runs over Phoenix Channel (WebSocket) for bidirectional streaming
**And** clarifying questions and user responses flow over a single connection

**Given** the planning conversation engine is implemented
**When** unit tests run
**Then** context query integration, adaptive depth logic, and conversation persistence are tested
**And** prompt assembly for planning is tested as a pure function
**And** near-100% coverage on planning engine module
**And** 100% coverage on `Planning.PromptAssembly` (critical module)

### Story 3.2: Spec Generation & Verification

As a user,
I want a thorough feature specification with verified assumptions and cited sources,
So that I can trust the spec before approving execution.

**Acceptance Criteria:**

**Given** the user ends the planning conversation (explicitly or via `fam plan` generating the spec) (FR23)
**When** the system generates a specification
**Then** the spec is a markdown file stored in the project directory (FR24)
**And** claims verified against the knowledge store and filesystem are marked ✓ (green)
**And** unverified assumptions are marked ⚠ (amber) and explicitly labeled
**And** context sources are cited inline (e.g., "✓ users table has email column — verified in db/migrations/001_init.sql")
**And** conventions are annotated (e.g., "Following existing pattern: handler/song.go")

**Given** verification runs during spec generation
**When** a claim references a file
**Then** verification is derived from the tool call log — only actual file reads count as verification (FR24)
**And** the LLM cannot self-report verification status
**And** claims citing files NOT in the tool call log are marked ⚠ unverified

**Given** the spec references files
**When** freshness is checked
**Then** the same freshness gate as task dispatch runs — stale files trigger re-scan before verification

**Given** spec generation is implemented
**When** unit tests run
**Then** verification mark logic is tested against known tool call logs
**And** spec markdown generation is tested for correct formatting
**And** 100% coverage on `Planning.Verification` (critical module)

**Given** a test project with known conventions and knowledge entries
**When** a spec is generated for a well-defined feature request
**Then** the spec demonstrates project-specific awareness (references actual conventions, files, and patterns from the test project — not generic output)

### Story 3.3: Streaming Reasoning Trail

As a user,
I want to see what the familiar is doing during planning in real time,
So that I can build trust in the spec being generated and understand how it verified assumptions.

**Acceptance Criteria:**

**Given** `fam plan` is generating a spec
**When** the planning engine makes tool calls (file reads, context queries, verification checks)
**Then** each conclusion is streamed to the terminal as a single line (FR24b)
**And** output is ~10-20 lines per spec, one per conclusion
**And** each line corresponds to actual tool use, not post-hoc narrative

**Given** the planning engine is working but hasn't produced output in 5+ seconds
**When** the heartbeat interval elapses
**Then** a heartbeat indicator is shown so the user knows the system is still working

**Given** the streaming trail is displayed
**When** the terminal is 80 columns wide
**Then** all trail output is legible without wrapping (UX-DR25)

**Given** this is the user's first `fam plan` (first ~3 sessions)
**When** the trail streams
**Then** progressive hints explain what each line means (UX-DR24)
**And** hints fade after approximately 3 planning sessions

**Given** the trail is implemented
**When** unit tests run
**Then** PubSub event publishing from planning engine is tested
**And** trail formatter is tested as a pure function (event → formatted string) separately from PubSub integration
**And** column width compliance at 80 columns is verified on formatter output
**And** near-100% coverage on trail module

### Story 3.4: Spec Review & Approval (CLI)

As a user,
I want to review and approve the generated spec via CLI or $EDITOR,
So that I can evaluate, approve, edit, or reject it before execution begins.

**Acceptance Criteria:**

**Given** a spec has been generated
**When** `fam plan` completes spec generation (FR25)
**Then** the spec markdown file is written to the project directory
**And** the CLI displays a summary: verification counts, convention count, unverified assumptions
**And** the user is prompted to approve, edit, or reject

**Given** the user wants to review the full spec
**When** `fam plan --editor` is used or the default editor flow triggers
**Then** the spec opens in `$EDITOR` for review
**And** on editor close, the user is prompted: approve (a), re-edit (e), or reject (r)

**Given** the user edited the spec externally
**When** the user returns to approve via CLI
**Then** the system stat-checks the spec file — if modified since generation, it re-reads and confirms the user wants to approve the edited version

**Given** the user approves the spec
**When** approval is confirmed
**Then** the spec is marked as approved (frontmatter updated) and task decomposition begins
**And** rejection returns to the planning conversation

**Given** spec review is implemented
**When** unit tests run
**Then** CLI approval flow, stat-check-on-approve, and editor integration are tested
**And** near-100% coverage on spec review logic

**Note:** Browser-rendered spec review with verification marks, keyboard shortcuts, and LiveView rendering is implemented in Epic 7 (Story 7.3) as an enhancement to this CLI flow. The "aha moment" (first spec rendered in browser) is delivered in Epic 7. Until then, spec review works via CLI summary + $EDITOR. The core planning value (context-aware conversation, verified assumptions) is fully functional in Epic 3.

### Story 3.5: Task Decomposition & Dependency Mapping

As a user,
I want the approved spec decomposed into an organized task hierarchy with dependencies,
So that execution can proceed in the correct order with no missing steps.

**Acceptance Criteria:**

**Given** the user approves a spec
**When** the system decomposes it (FR26)
**Then** an epic is created with groups and ordered tasks
**And** groups represent functional slices — generated only when 2+ distinct functional areas exist
**And** single-area features produce Epic → Tasks directly, skipping the group level
**And** each task has dependencies explicitly mapped
**And** work hierarchy Ecto schemas (epics, groups, tasks, subtasks) and migrations are created if not already present
**And** the `Work` context schemas are functional independently of decomposition — Epic 4 can query empty tables, state machine operates on any task regardless of how it was created

**Given** tasks are generated
**When** the user reviews the task list (FR27)
**Then** tasks are displayed with dependencies, grouping, and estimated scope
**And** the user can approve, request regrouping, or modify the decomposition

**Given** task decomposition produces acceptance checks
**When** each task is created
**Then** the task includes a structured list of "this task should: [x, y, z]" extracted from the spec
**And** these checks are used later by the validation pipeline

**Given** decomposition is implemented
**When** unit tests run
**Then** decomposition logic is tested for single-area and multi-area features
**And** dependency mapping correctness is verified
**And** 100% coverage on `Work.DependencyResolver` (critical module)

### Story 3.6: Cross-Plan Conflict Detection & Plan Freshness

As a user,
I want the system to detect conflicts between new tasks and existing work, and warn me if plans are stale,
So that I don't accidentally create conflicting changes or execute on outdated assumptions.

**Acceptance Criteria:**

**Given** the user generates a new task list via `fam plan`
**When** the system checks for conflicts with existing tasks in the tracker (FR28)
**Then** file-level conflicts are identified (two tasks intending to modify the same file)
**And** dependency conflicts are identified (new tasks depending on incomplete existing tasks)

**Given** conflicts are detected
**When** the system presents resolution options (FR29)
**Then** the user can choose to: reorder, merge, defer, or proceed with awareness
**And** the chosen resolution is applied to the task tracker

**Given** a plan exists and time has passed
**When** the user dispatches execution (FR31)
**Then** the system checks if referenced files changed since plan creation
**And** warns if the plan is >24h stale and files have changed
**And** checks if files created by completed dependency tasks still exist

**Given** conflict detection and freshness are implemented
**When** unit tests run
**Then** file-level and dependency conflict detection are tested
**And** freshness validation with Clock mock is tested
**And** near-100% coverage on conflict and freshness modules

---

### Story 3.7: Planning Pipeline Integration Test

As a developer,
I want an integration test that validates the full planning pipeline end-to-end,
So that I can prove conversation, spec generation, verification, and decomposition work together.

**Acceptance Criteria:**

**Given** the planning pipeline integration test runs
**When** the golden path executes
**Then** the full flow is validated: initiate planning conversation → query knowledge store for context → LLM generates clarifying questions (mocked) → generate spec with verification marks from tool call log → persist conversation in planning_messages → decompose spec into task hierarchy with dependencies
**And** real SQLite via Ecto sandbox for knowledge queries, conversation persistence, and task creation
**And** LLM provider mocked via Mox with scripted conversation and spec generation responses

**Given** failure scenarios are tested
**When** the integration test exercises error paths
**Then** conversation resume after interruption replays history correctly
**And** verification marks match tool call log (no false ✓ marks)
**And** decomposition produces valid dependency graph (no cycles)
**And** plan freshness validation catches stale referenced files

**Epic 3 Summary:** 7 stories, covering FR20-FR31. All 13 FRs addressed.

## Epic 4: Task Management

User can organize, track, reorder, and manage work across features with a four-level hierarchy (Epic → Group → Task → Subtask), drill-down navigation, file modification tracking, and epic lifecycle management.

### Story 4.1a: Task State Machine

As a developer,
I want a pure-logic state machine governing task status transitions,
So that task lifecycle is deterministic, well-tested, and impossible to corrupt.

**Acceptance Criteria:**

**Given** the state machine governs task transitions
**When** a task status changes
**Then** only valid transitions are allowed (ready → in-progress → validating → complete/failed/blocked)
**And** invalid transitions produce `{:error, {:invalid_transition, details}}`
**And** the `Work.TaskStateMachine` module is pure logic with no side effects

**Given** tasks have subtasks
**When** status rolls up through the hierarchy
**Then** any failed subtask = task ❌, self-repaired subtask = task 🔧, all green = task ✅
**And** the same roll-up applies at every hierarchy level (task → group → epic)
**And** the `Work.Triage` module implements roll-up as pure logic

**Given** the state machine is implemented
**When** unit tests run
**Then** 100% coverage on `Work.TaskStateMachine` (critical module)
**And** property-based tests with StreamData verify: no sequence of valid transitions reaches an illegal state
**And** triage roll-up logic has near-100% coverage with property tests verifying: roll-up is consistent regardless of subtask completion order

### Story 4.1b: Work Hierarchy Display

As a user,
I want to view my work organized in a hierarchical structure with clear status indicators,
So that I can quickly assess progress and identify what needs attention.

**Acceptance Criteria:**

**Given** tasks exist in the work tracker (created by planning decomposition)
**When** the user runs `fam tasks` (FR32)
**Then** the four-level hierarchy is displayed: Epic → Group → Task → Subtask
**And** each item shows status using the state machine's current state
**And** items are sorted worst-first: ❌ → 🔧 → ⊘ → ✅
**And** drill-down navigation shows hierarchy context (e.g., "Epic: User Accounts > Group: Authentication")
**And** empty levels collapse (trivial features show Epic → Tasks directly)

**Given** the display renders output
**When** `--json` flag is provided
**Then** the hierarchy is returned as structured JSON matching the documented schema
**And** CLI output is legible at 80 columns (UX-DR25)

**Given** the display is implemented
**When** unit tests run
**Then** sorting, drill-down, collapsing, and JSON output are tested
**And** near-100% coverage on display and formatting modules

### Story 4.2: Task Priority & Removal

As a user,
I want to reorder task priorities and remove tasks I no longer need,
So that I can adjust my work plan as requirements change.

**Acceptance Criteria:**

**Given** tasks exist in the work tracker
**When** the user reorders task priority (FR33)
**Then** the new priority order is persisted
**And** dependency ordering is preserved — a task cannot be prioritized above its dependencies
**And** `fam tasks` reflects the updated order

**Given** a task has dependent tasks
**When** the user removes it (FR34)
**Then** a warning is displayed listing all tasks that depend on the removed task
**And** the user confirms before removal proceeds
**And** dependent tasks are marked as blocked or the user chooses to remove the chain

**Given** priority and removal operations are implemented
**When** unit tests run
**Then** priority reordering with dependency constraints is tested
**And** removal cascading and warning logic is tested
**And** near-100% coverage on priority and removal functions

### Story 4.3: File Modification Tracking & Epic Lifecycle

As a user,
I want to see which tasks modified specific files and manage epic lifecycle,
So that I can trace changes back to their source and keep my work tracker clean.

**Acceptance Criteria:**

**Given** tasks have executed and modified files
**When** the user runs `fam tasks --modified-files <path>` (FR35)
**Then** all tasks that modified the specified file are listed with their status and modification details

**Given** all tasks in an epic are complete
**When** the system detects epic completion (FR36)
**Then** the user is prompted to archive the epic
**And** archived epics are hidden from default `fam tasks` output but accessible via `fam tasks --archived`

**Given** the user wants to discard an epic
**When** `fam discard` or equivalent command is run on an epic (FR37)
**Then** the epic's spec file and all associated groups/tasks are removed from the tracker
**And** the user confirms before deletion proceeds

**Given** file tracking and lifecycle are implemented
**When** unit tests run
**Then** file modification queries, archival logic, and discard with cleanup are tested
**And** near-100% coverage on file tracking and lifecycle modules

---

**Epic 4 Summary:** 4 stories (4.1a, 4.1b, 4.2, 4.3), covering FR32-FR37. All 6 FRs addressed.

## Epic 5: Task Execution & Validation

User can dispatch tasks and receive validated, convention-following code produced by context-aware agents. **Agents are Actors: each agent task is a GenServer under a DynamicSupervisor** — agent state (conversation history, task context, tool permissions) lives in GenServer state, the tool-call loop uses `handle_continue`/`handle_info` (not a recursive function), inter-agent coordination uses message passing, and supervisor strategies handle crash recovery. This is the core reason BEAM/OTP was chosen. Execution includes automatic self-validation (test/build/lint/coverage/duplicate checks), atomic rollback on failure, cascading dependency handling, provider resilience, and thesis validation through provider comparison and ablation testing. Safety constraints enforced throughout.

### Story 5.1: Agent Runner & Tool Call Loop

As a user,
I want the system to execute tasks by sending prompts to an LLM and iteratively calling tools until the work is done,
So that code is generated through an intelligent, supervised execution loop.

**Acceptance Criteria:**

**Given** a task is dispatched for execution
**When** the agent runner starts
**Then** a supervised agent process is spawned via `DynamicSupervisor`
**And** the tool call loop executes: send prompt → receive response → if tool calls, parse and execute each → append results to message history → repeat until no more tool calls, max iterations reached, or error
**And** the agent can read actual project files from the filesystem at execution time via `read_file` tool (FR41)
**And** relevant knowledge entries are injected into the agent prompt before execution (FR42)
**And** prompt assembly is a pure function returning `{prompt, %{truncated: boolean, dropped_entries: list, token_budget: map}}`

**Given** the agent runner is executing
**When** context injection prepares the prompt
**Then** the prompt includes: task description, relevant knowledge entries, role definition, conventions, and provider-specific formatting (FR42, FR43)
**And** context window budget is managed — most relevant context prioritized when approaching limits (NFR18)
**And** truncation metadata is accurate

**Given** safety limits are configured
**When** the agent executes
**Then** max tool calls per task (~100 default) are enforced — runner aborts if exceeded
**And** per-task timeout triggers rollback on expiration
**And** writes to files outside the intended files list produce warnings (logged, not blocked)
**And** every LLM response is logged in full to `.familiar/logs/` for post-hoc review

**Given** the agent runner is implemented
**When** unit tests run
**Then** tool call loop is tested with scripted LLM responses via Mox
**And** safety limit enforcement (max calls, timeout) is tested
**And** 100% coverage on `Planning.PromptAssembly` (critical module)
**And** near-100% coverage on agent runner module

**Note:** The agent runner's `write_file` tool handler uses direct file writes initially. Story 5.2 (File Transaction Module) replaces direct writes with atomic transaction-logged writes. Until 5.2 is complete, file writes are not crash-safe.

### Story 5.2: File Transaction Module

As a user,
I want all file writes to be atomic with clean rollback on failure,
So that a crashed or cancelled task never leaves my project in a broken state.

**Acceptance Criteria:**

**Given** the agent writes a file during execution
**When** the file transaction module processes the write
**Then** the strict write sequence is followed: (1) log write intent to SQLite → (2) write file to disk → (3) log completion to SQLite
**And** crash between steps 1-2: rollback finds intent without file, nothing to clean
**And** crash between steps 2-3: rollback finds intent without completion, deletes written file

**Given** a file is about to be written
**When** the pre-write stat check runs (immediately before step 2)
**Then** if the file's current content hash differs from the hash recorded at task start → skip write, save as `.fam-pending`, log conflict (FR56b)
**And** comparison uses content hash (not just mtime) to catch modifications between agent-read and agent-write
**And** the agent receives a "file changed" signal and handles gracefully

**Given** a rollback is triggered (task failure, cancellation, or crash recovery)
**When** the rollback function executes
**Then** each file's rollback has its own status (pending/rolled-back/skipped)
**And** re-running rollback after partial completion finishes remaining files without double-reverting (idempotent)
**And** file modifications are tracked per task for downstream analysis (FR55)

**Given** `.fam-pending` files exist
**When** `fam status` is run
**Then** pending conflict files are reported in the output

**Given** the file transaction module is implemented
**When** unit tests run
**Then** 100% coverage on `Files.TransactionLog` (critical module)
**And** property-based tests with StreamData verify: rollback after any crash point leaves filesystem in a consistent state
**And** idempotent rollback is tested with partial completion scenarios

### Story 5.3: Safety Enforcement

As a user,
I want the system to enforce strict safety constraints on all agent actions,
So that agents cannot damage my project, leak secrets, or perform unauthorized operations.

**Acceptance Criteria:**

**Given** an agent attempts to read or write a file
**When** the tool handler processes the request
**Then** the path is validated to be within the project directory only (FR58)
**And** attempts to access paths outside the project directory are rejected with a clear error
**And** the project directory is resolved to its canonical path — symlinks within the project are followed but the resolved path must still be within the canonical project directory

**Given** an agent attempts to commit to git
**When** the tool handler processes the request
**Then** the commit is blocked unless explicit user approval was given (FR59)

**Given** an agent attempts to delete a file
**When** the tool handler processes the request
**Then** deletion is allowed only for files created by the current task (FR60)
**And** attempts to delete pre-existing files are rejected

**Given** an agent attempts to execute a shell command
**When** the tool handler processes the request
**Then** only commands defined in the language configuration (test, build, lint) are allowed (FR61)
**And** arbitrary shell commands are rejected

**Given** the user dispatches a task with `--provider anthropic` (external provider)
**When** it's the first external API call in this session
**Then** a confirmation warning is shown (FR64)
**And** the warning re-prompts after >1 hour of inactivity

**Given** safety enforcement is implemented
**When** unit tests run
**Then** every safety constraint is tested with both allowed and rejected cases
**And** near-100% coverage on tool handler and safety modules

### Story 5.4: Task Dispatch & Execution Modes

As a user,
I want to execute tasks individually, in batches, or all at once with real-time streaming,
So that I can choose the right execution strategy for my workflow.

**Acceptance Criteria:**

**Given** tasks are ready in the tracker
**When** the user runs execution commands (FR38)
**Then** `fam do` executes the highest-priority ready task
**And** `fam do #N` executes a specific task by ID
**And** `fam do --batch N` executes the next N ready tasks in sequence
**And** `fam do --all` executes all tasks in dependency/priority order
**And** `fam do --all` shows a brief status line before starting: "Executing: 15 tasks (User Accounts)" (UX-DR18)

**Given** a task is executing
**When** the user runs `fam cancel` (FR44)
**Then** the running task is stopped
**And** in-progress file changes are rolled back via the transaction module

**Given** the user wants to use a specific provider
**When** `fam do #N --provider anthropic` is run (FR45)
**Then** the task executes with the specified provider instead of the default

**Given** a task is executing
**When** agent activity occurs
**Then** activity is streamed to the user in real time via PubSub (FR46)
**And** the streaming output works in a half-screen terminal pane

**Given** a batch execution completes
**When** all tasks finish or fail
**Then** an execution summary is generated: tasks completed, retries, failures, tests added, files modified (FR47)

**Given** a task has completed (success or failure)
**When** the user runs `fam review #N`
**Then** the post-task detail is displayed: file diff, context entries injected, tool calls made, self-repair status (if retried), and validation results
**And** `--json` outputs the review data as structured JSON

**Given** dispatch modes and review are implemented
**When** unit tests run
**Then** each dispatch mode is tested (single, batch, all, by ID)
**And** cancel with rollback is tested
**And** provider override is tested
**And** `fam review` output formatting is tested
**And** near-100% coverage on dispatch and execution mode logic

### Story 5.5: Multi-Step Workflows

As a user,
I want tasks to execute multi-step workflows where each step builds on the previous,
So that complex tasks are broken into manageable agent steps with appropriate interaction modes.

**Acceptance Criteria:**

**Given** a workflow definition with multiple steps
**When** the system executes the workflow (FR39)
**Then** each step's output is available to subsequent steps via an accumulated context map — each step receives `%{previous_steps: [%{step: name, output: result}]}` in its context
**And** context accumulates through the workflow pipeline

**Given** a workflow has both interactive and autonomous steps
**When** execution reaches an interactive step (FR40)
**Then** a multi-turn conversation with the user begins (via Phoenix Channel)
**And** the user can respond, and the conversation continues until the step completes
**When** execution reaches an autonomous step
**Then** the step runs to completion without user input

**Given** workflow execution is implemented
**When** unit tests run
**Then** step chaining with output passing is tested
**And** interactive vs autonomous step modes are tested
**And** near-100% coverage on workflow execution module

### Story 5.6: Validation Pipeline

As a user,
I want every task's output automatically validated against tests, builds, lints, and requirements,
So that I can trust that generated code meets quality standards before it's marked complete.

**Acceptance Criteria:**

**Given** a task has completed code generation
**When** the validation pipeline runs (FR48)
**Then** configured test command is executed and evaluated by exit code
**And** configured build command is executed and evaluated by exit code
**And** configured lint command is executed and evaluated by exit code
**And** each element of the task description is checked for coverage (requirement coverage validation)
**And** generated code is checked against existing codebase for unnecessary duplication

**Given** validation fails on an autonomous step
**When** the system handles the failure (FR49)
**Then** the step is retried once with the failure context injected
**And** if retry also fails, the task is aborted

**Given** a workflow has multiple steps and one failed
**When** the system needs to restart (FR51)
**Then** execution resumes from the failed step without replaying completed steps

**Given** the validation pipeline is implemented
**When** unit tests run
**Then** 100% coverage on `Execution.ValidationPipeline` (critical module)
**And** property-based tests verify: pipeline runs all applicable validators and never silently skips one
**And** retry logic and restart-from-failed-step are tested

### Story 5.7: Reliability & Provider Resilience

As a user,
I want execution to handle cascading failures gracefully and recover from provider outages,
So that unattended runs complete as much work as possible without corrupting state.

**Acceptance Criteria:**

**Given** a task fails that other tasks depend on
**When** cascading dependency failure handling runs (FR52)
**Then** dependent tasks are skipped (marked blocked)
**And** independent tasks continue executing
**And** the failure chain is reported clearly

**Given** the LLM provider becomes unavailable during execution
**When** the system detects the failure (FR53)
**Then** retry with exponential backoff is attempted
**And** after configurable retry threshold, execution pauses
**And** paused tasks are marked as `⊘ provider unavailable`
**And** when the provider returns, paused tasks resume automatically

**Given** a task fails
**When** the failure is detected (FR54)
**Then** failure is reported within 30 seconds with explanation and rollback status
**And** the error includes `{:error, {type, details}}` with structured information

**Given** the daemon starts after an unclean shutdown
**When** interrupted state detection runs (FR56)
**Then** partial file changes are rolled back via the transaction module
**And** tasks in `in-progress` or `validating` state are reconciled against the transaction log
**And** tasks with no recovery data are marked as `failed: interrupted — no recovery data`

**Given** reliability features are implemented
**When** unit tests run
**Then** cascading failure scenarios are tested with various dependency graphs
**And** provider failure, retry, pause, and resume are tested with Mox
**And** crash recovery with orphaned task reconciliation is tested
**And** near-100% coverage on reliability modules

### Story 5.8: Thesis Validation

As a user,
I want to compare local model output against frontier models with and without context injection,
So that I can validate whether institutional memory actually improves code quality.

**Acceptance Criteria:**

**Given** the user wants to compare providers
**When** `fam do #N --provider anthropic` is run alongside a local execution (FR70)
**Then** both executions are logged with full details: provider, injected context, tool calls, validation results
**And** results are reviewable via `fam review #N`

**Given** the user wants to run an ablation test
**When** context injection is disabled for a task execution
**Then** the task executes without knowledge store context injected into the prompt
**And** the execution is logged with `ablation: true` flag for comparison

**Given** thesis validation executions complete
**When** the user reviews results
**Then** all data needed for comparison is available: injected context entries, provider used, execution details, validation pass/fail, acceptance decision
**And** comparison is post-hoc analysis (manual during baseline phase), not automated scoring

**Given** thesis validation is implemented
**When** unit tests run
**Then** ablation flag correctly disables context injection in prompt assembly
**And** execution logging captures all required comparison data
**And** near-100% coverage on thesis validation hooks

---

### Story 5.9: Execution Pipeline Integration Test

As a developer,
I want an integration test that validates the full execution and validation pipeline end-to-end,
So that I can prove dispatch, agent execution, file transactions, validation, and rollback work as a coherent system.

**Acceptance Criteria:**

**Given** the execution pipeline integration test runs
**When** the golden path executes
**Then** the full flow is validated: dispatch task → prompt assembly with context injection → tool call loop with mocked LLM (scripted file writes) → file writes via transaction module in real SQLite → validation pipeline runs (mocked shell for test/build/lint) → task marked complete with execution log
**And** real SQLite via Ecto sandbox for transaction log, execution log, and task status
**And** LLM, Shell, and FileSystem behaviours mocked via Mox

**Given** failure scenarios are tested
**When** the integration test exercises error paths
**Then** task failure triggers atomic rollback — all file writes for the task are reverted via transaction log
**And** cancel mid-execution triggers rollback of in-progress writes
**And** validation failure triggers retry once, then abort with rollback
**And** cascading dependency failure skips dependent tasks and continues independents
**And** safety enforcement blocks writes outside project directory and unauthorized deletions
**And** daemon responds to `GET /api/health` within 1 second while a task is executing (NFR4)

**Given** the provider failure path is tested
**When** the LLM mock simulates provider unavailability
**Then** retry with backoff is attempted, then execution pauses
**And** paused tasks resume when provider returns

**Epic 5 Summary:** 9 stories, covering FR38-FR56b, FR58-FR61, FR64, FR70. All 26 FRs addressed.

## Epic 6: Recovery

User can fix failures at any hierarchy level with `fam fix` — the system pre-analyzes failures, identifies ambiguities, and proposes concrete resolution options. Autonomous self-repair handles what it can before involving the user.

### Story 6.1: Unified Recovery (`fam fix`)

As a user,
I want to fix failures with a single command that already understands what went wrong,
So that recovery is fast, informed, and doesn't require me to investigate the failure myself.

**Acceptance Criteria:**

**Given** a task has failed
**When** `fam fix #N` is run (FR57)
**Then** the fix conversation opens with the failure already analyzed
**And** the failure analysis includes: error type, failed step/subtask, files involved, relevant knowledge entries that were injected, and the specific ambiguity or root cause
**And** concrete resolution options are proposed with rationale (e.g., "Cookie-based sessions (consistent with 3 web handlers) or Token-based (consistent with 2 API handlers)?")
**And** the user selects an approach and the system generates a replacement task

**Given** the user doesn't know which task to fix
**When** `fam fix` is run without an argument (FR57)
**Then** a Telescope-style picker opens showing all failed/blocked items
**And** picker results include hierarchy level context: `[epic] User Accounts`, `[group] Authentication`, `[task] #5 Add login handler`
**And** the user selects what to fix

**Given** no tasks have failed or are blocked
**When** `fam fix` is run
**Then** the picker shows an empty state: "Nothing to fix — all tasks are complete or ready"

**Given** the user fixes at the group or epic level
**When** `fam fix` targets a group or epic
**Then** all file changes for that scope are reverted via Familiar's transaction log (not git)
**And** a planning conversation opens pre-loaded with failure context
**And** a new spec is generated that avoids the same mistakes

**Given** the fix conversation runs
**When** the user interacts with the system
**Then** the conversation runs over Phoenix Channel (interactive mode)
**And** after the user selects a resolution, `fam do --all` can resume with the fix applied and blocked tasks unblocked

**Given** unified recovery is implemented
**When** unit tests run
**Then** failure analysis and option generation are tested with various failure types
**And** picker integration, hierarchy-level fix, and conversation flow are tested
**And** near-100% coverage on recovery module

### Story 6.2: Autonomous Self-Repair

As a user,
I want the system to automatically fix what it can before asking me for help,
So that I only see failures that genuinely require my judgment.

**Acceptance Criteria:**

**Given** a task fails during unattended execution
**When** the self-repair system evaluates the failure (FR57b)
**Then** if the error is recoverable (stale context, transient provider issue): the system refreshes context and retries automatically
**And** maximum 1 retry per failure — if retry fails, escalate immediately to ❌ (no retry loops)
**And** if retry succeeds: the task is marked 🔧 (self-repaired), not ✅
**And** if retry fails: the task is escalated to ❌ (needs input) for user triage

**Given** self-repair runs during a batch execution
**When** multiple tasks fail
**Then** each failure is independently evaluated for recoverability via `recoverable?/1`
**And** self-repair does not block independent task execution
**And** the user sees only genuinely ambiguous failures when they return

**Given** self-repair refreshes context before retry
**When** the retry executes
**Then** the refreshed context is injected into the new prompt
**And** domain knowledge from the failed attempt is NOT captured (only failure gotchas from the failure reason)

**Given** 3 or more tasks fail with the same error type during a batch execution
**When** the self-repair system evaluates the next failure with the same error type
**Then** retry is skipped — all remaining tasks with that error type are escalated to ❌ immediately (circuit breaker pattern)

**Given** autonomous self-repair is implemented
**When** unit tests run
**Then** recoverable vs non-recoverable failure routing is tested
**And** context refresh + retry flow is tested
**And** self-repair during batch with independent task continuation is tested
**And** circuit breaker triggers after 3 same-type failures
**And** near-100% coverage on self-repair module

---

**Epic 6 Summary:** 2 stories, covering FR57-FR57b. All 2 FRs addressed.

## Epic 7: Web UI

User can review specs in the browser with verification marks and keyboard shortcuts, triage work through a worst-first dashboard, search everything via Telescope-style picker, browse the knowledge store, and observe execution in real time — all through a zero-chrome, keyboard-first LiveView interface.

**Parallelization note:** Stories 7.1a-7.6 (design system, test infrastructure, spec renderer, search picker, keyboard navigation) are buildable without Epic 5 (Execution). Stories 7.4 (triage), 7.7 (activity feed), and 7.8 (notifications) depend on execution data. This epic can be parallelized with Epics 5-6 during sprint planning if execution-dependent stories are scheduled after Epic 5 completes.

### Story 7.1a: CSS Design System & Zero-Chrome Layout

As a user,
I want a clean, dark, terminal-adjacent web interface with no visual noise,
So that the web UI feels like a natural extension of my terminal workflow.

**Acceptance Criteria:**

**Given** the web UI is accessed in a browser
**When** the page loads
**Then** the layout is zero-chrome — no sidebar, no top nav, no breadcrumbs (UX-DR22)
**And** all default Phoenix layout elements are stripped
**And** the only persistent UI element is the status bar fixed at the bottom
**And** the LiveView web UI is served on a localhost port, auto-starting with the daemon — no separate setup required (FR71)

**Given** the design system is implemented
**When** CSS is inspected
**Then** all styling uses CSS custom properties as design tokens (UX-DR1)
**And** the color palette is semantic: green/amber/red for triage, health, verification (UX-DR3)
**And** dual-density typography is applied: tool density (~0.8-0.85rem, line-height ~1.3) for dashboards, reading density (~0.95rem, line-height ~1.5-1.6) for prose (UX-DR4)
**And** two font stacks are used: monospace for tool elements, system-ui sans-serif for reading (UX-DR5)
**And** the five-step spacing scale (xs-xl) is defined (UX-DR6)

**Given** accessibility requirements
**When** the UI is audited
**Then** primary text contrast ≥7:1 (AAA), muted text ≥4.5:1 (AA) (UX-DR7)
**And** visible focus indicators use accent-blue outline
**And** no keyboard traps — `Esc` always exits

**Given** the design system is implemented
**When** tests run
**Then** LiveView component rendering tests verify correct CSS classes and token usage
**And** accessibility contrast ratios are documented with computed values (visual regression is out of scope for MVP)
**And** zero-chrome layout is verified (no default Phoenix elements present)

### Story 7.1b: Status Bar, Notifications & Error Communication

As a user,
I want persistent status context, ephemeral feedback on my actions, and clear error communication,
So that I always know what actions are available and what the system state is.

**Acceptance Criteria:**

**Given** the status bar component is rendered
**When** the user is in any view
**Then** the status bar shows context-specific keybindings (UX-DR8)
**And** it has `role="status"` with live region for screen readers
**And** global status indicator appears above the status bar only when there's a system-level state to communicate (UX-DR16)

**Given** toast notifications fire
**When** a user action completes
**Then** ephemeral messages appear above the status bar and auto-dismiss (3-5s) (UX-DR16)
**And** max 3 stacked, oldest dismissed first
**And** toasts never steal keyboard focus

**Given** a view has no content
**When** it renders
**Then** an empty state is shown with one-sentence explanation + one-sentence next action (UX-DR17)

**Given** a system error occurs
**When** the error is displayed
**Then** severity levels are distinguished: recoverable (auto-retry indicator), blocking (global status), degraded (global status), fatal (full-screen with recovery command) (UX-DR20)

**Given** status bar and notifications are implemented
**When** tests run
**Then** status bar content updates based on view context are tested
**And** toast stacking, auto-dismiss timing, and max count are tested
**And** empty state rendering for each view is tested
**And** error severity display routing is tested
**And** near-100% coverage on status bar, toast, and error communication components

### Story 7.2: LiveView Test Infrastructure & Integration Scaffold

As a developer,
I want LiveView test helpers and integration scaffolding established before building components,
So that every subsequent component story has reusable test utilities for keyboard events, PubSub assertions, and view transitions.

**Acceptance Criteria:**

**Given** the Web UI test infrastructure is being established
**When** LiveView test helpers are created
**Then** test helpers exist for: simulating keyboard events (phx-keydown), asserting PubSub-driven updates, and verifying view transitions
**And** these helpers are reusable across all LiveView component tests
**And** ExUnit case templates for LiveView tests with PubSub setup are available

**Given** the integration scaffold runs
**When** the golden path executes
**Then** view navigation works end-to-end: `s` → spec view, `t` → triage view, `w` → watch view, `l` → library view, `?` → help overlay, `Esc` → return
**And** `Space` opens the search picker from any view and `Esc` closes it
**And** PubSub events trigger live updates in triage view (status change reflected within test assertion window)
**And** spec review → approve triggers decomposition flow

**Given** component interaction is tested
**When** the triage view renders with test data
**Then** worst-first sorting is correct, drill-down via `Enter` shows children, `Esc` returns
**And** search picker returns results and preview updates on navigation

**Given** failure scenarios are tested
**When** the integration test exercises error paths
**Then** system error states render the correct global status indicator
**And** empty states render correctly for each view
**And** toast notifications stack and auto-dismiss correctly

**Note:** This story is intentionally positioned early in Epic 7. All subsequent component stories (7.3-7.9) use these test helpers. The integration assertions grow as components are built.

### Story 7.3: Spec Renderer & Review

As a user,
I want to review generated specs in a beautifully rendered browser view with interactive controls,
So that I can quickly evaluate spec quality and approve or reject with confidence.

**Acceptance Criteria:**

**Given** a spec has been generated by `fam plan`
**When** the browser auto-opens to the spec review page (FR72)
**Then** the page loads in under 1 second (NFR5)
**And** auto-open is configurable; degrades gracefully if browser unavailable (URL printed to terminal)
**And** subsequent specs in the same session update the existing tab via LiveView

**Given** the spec is rendered
**When** the user reads the content (FR73)
**Then** markdown is rendered at reading density with max-width ~72ch
**And** inline verification marks appear: ✓ green for verified, ⚠ amber for unverified (UX-DR11)
**And** convention annotations appear in muted italic
**And** knowledge links have dotted underline on keyboard focus, navigable via Tab
**And** metadata line shows trust summary: "Generated [date] · N verified · N unverified · N conventions applied"

**Given** the user wants to act on the spec
**When** keyboard shortcuts are pressed (FR74)
**Then** `a` approves the spec (triggers decomposition)
**And** `e` opens spec in `$EDITOR` (or in-browser if configured)
**And** `r` rejects the spec and returns to planning conversation
**And** `d` shows diff from previous version
**And** `c` shows all context entries that influenced the spec
**And** the status bar shows all available actions

**Given** spec review is implemented
**When** tests run
**Then** markdown rendering with verification marks is tested
**And** keyboard shortcut dispatch is tested
**And** auto-open and LiveView update logic is tested
**And** near-100% coverage on spec renderer component

### Story 7.4: Triage Dashboard & Work Hierarchy

As a user,
I want a triaged dashboard showing work status at a glance with drill-down navigation,
So that after an unattended run I can quickly see what succeeded, what self-repaired, and what needs me.

**Acceptance Criteria:**

**Given** tasks exist with various statuses
**When** the user navigates to the triage view (`t` keybinding) (FR75)
**Then** items are grouped by feature/epic with worst-first sort: ❌ → 🔧 → ⊘ → ✅ (UX-DR10)
**And** each group shows a summary line: "accounts (3/5 ✅ 1 🔧 1 ❌)"
**And** items display: status icon, task ID, title, failure summary or self-repair note

**Given** the triage dashboard is displayed
**When** status changes occur during execution
**Then** badges update in real-time via LiveView PubSub (UX-DR10)
**And** updates are delivered within 100ms of server-side event (NFR6)
**And** rows don't re-sort during live updates; re-entering the view refreshes sort

**Given** the user navigates the hierarchy (UX-DR12)
**When** `Enter` is pressed on a group or epic
**Then** the view drills into that level showing its children
**And** a depth indicator header shows position: "Epic: User Accounts > Group: Authentication"
**And** `Esc` returns to the previous level
**And** `j`/`k` navigates items within the current level
**And** `f` on a failed task opens the fix flow

**Given** the triage dashboard is implemented
**When** tests run
**Then** worst-first sorting is tested with various status combinations
**And** drill-down navigation and hierarchy rendering are tested
**And** PubSub-driven live updates are tested
**And** near-100% coverage on triage and work hierarchy components

### Story 7.5: Search Picker (Telescope)

As a user,
I want a universal search overlay that finds anything across context, tasks, specs, and files,
So that I can navigate the entire system with one interaction pattern.

**Acceptance Criteria:**

**Given** the user is in any web UI view
**When** `Space` is pressed (FR76)
**Then** a Telescope-style search picker overlay appears (UX-DR9)
**And** the overlay has a split pane: results on the left, preview on the right

**Given** the user types a search query
**When** characters are entered
**Then** text matches appear instantly (<50ms) (UX-DR9)
**And** semantic results stream in within 200ms
**And** the list populates immediately and gets better — no loading spinner

**Given** results are displayed
**When** the user navigates with `j`/`k`
**Then** the preview pane updates to show content plus linked knowledge trail
**And** `Tab` follows a link within the picker (navigating the knowledge graph without leaving search)
**And** `Enter` goes to the selected result
**And** `Esc` closes the picker

**Given** the search picker works across all entity types
**When** results return
**Then** results include context entries, tasks, specs, and files with type indicators
**And** the same interaction model is used everywhere (CLI `fam search`, web UI picker)

**Given** the search picker is implemented
**When** tests run
**Then** two-phase rendering (instant text + streaming semantic) is tested
**And** keyboard navigation, linked preview, and cross-entity search are tested
**And** near-100% coverage on search picker component

### Story 7.6: Keyboard Navigation & Help

As a user,
I want every action reachable by keyboard with a discoverable help overlay,
So that I never need to reach for the mouse and can learn the UI quickly.

**Acceptance Criteria:**

**Given** the web UI is loaded
**When** the user presses view navigation keys (FR77)
**Then** `s` goes to spec view, `t` to triage, `w` to watch, `l` to library, `?` to help, `Esc` closes/returns
**And** `Space` opens the search picker from any view

**Given** the user is within a view
**When** vim-style navigation keys are pressed (UX-DR21)
**Then** `j`/`k` moves between items, `Enter` selects/expands
**And** view-specific actions are shown in the status bar

**Given** the user presses `?`
**When** the help overlay renders (UX-DR15)
**Then** a single-screen keybinding reference is displayed organized by view context
**And** all keybindings fit on one screen without scrolling
**And** the overlay uses monospace, tool density formatting
**And** `Esc` dismisses the overlay

**Given** accessibility is implemented (UX-DR7)
**When** a screen reader accesses the UI
**Then** the picker overlay has `role="dialog"`
**And** verification marks have aria-labels ("verified"/"unverified")
**And** triage blocks have full status text labels
**And** focus order follows visual order

**Given** the user wants custom keybindings (UX-DR23)
**When** `.familiar/config.toml` contains keybinding overrides
**Then** all keybindings are remapped accordingly
**And** colors are configurable via the same config

**Given** keyboard navigation is implemented
**When** tests run
**Then** all view navigation shortcuts are tested
**And** vim-style navigation within views is tested
**And** help overlay rendering and dismissal are tested
**And** accessibility ARIA attributes are verified
**And** near-100% coverage on keyboard navigation and help modules

### Story 7.7: Activity Feed & Knowledge Browser

As a user,
I want to watch execution in real time and browse the knowledge store visually,
So that I have ambient awareness of what the familiar is doing and can explore what it knows.

**Acceptance Criteria:**

**Given** a task is executing
**When** the user navigates to the watch view (`w` keybinding) (UX-DR13)
**Then** streaming structured output shows: current task and group, file reads/writes, convention applications, subtask progress checklist (✅/◐/○)
**And** completed tasks stack below the current activity
**And** display uses tool density — every line is informational
**And** updates are real-time via PubSub
**And** if nothing is executing, the view shows last run summary

**Given** the user navigates to the library view (`l` keybinding) (UX-DR14)
**When** the knowledge browser renders
**Then** entries are listed with type badge, one-line summary, and date
**And** inline search filters as-you-type with two-phase rendering
**And** type filter tabs toggle entry categories (all/decision/fact/convention/gotcha/relationship)
**And** `Enter` shows full entry content with linked artifacts (referenced specs, tasks, source files)

**Given** an entry is selected in the library
**When** the preview renders
**Then** it shows: entry type, source, freshness status, full content, and "Referenced by" links
**And** `d` deletes the selected entry

**Given** activity feed and knowledge browser are implemented
**When** tests run
**Then** streaming activity display and PubSub integration are tested
**And** knowledge browser search, filtering, and preview are tested
**And** near-100% coverage on activity feed and knowledge browser components

### Story 7.8: Notifications & Progressive Onboarding

As a user,
I want OS-native notifications when execution completes and gentle onboarding guidance on first use,
So that I'm informed without watching and the learning curve is smooth.

**Acceptance Criteria:**

**Given** the system supports OS notifications (FR79)
**When** execution completes or pauses
**Then** an OS-native notification is sent (auto-detect `terminal-notifier` on macOS, `notify-send` on Linux)
**And** notification provider is configurable in `fam config`
**And** if no provider is detected, notifications degrade gracefully (user pulls with `fam status`)

**Given** `fam watch` is run in the terminal (UX-DR27)
**When** a task is executing
**Then** a structured real-time activity display shows in the terminal
**And** the display works in a narrow tmux split
**And** `q` detaches from watch; execution continues regardless

**Given** it's the user's first few sessions (UX-DR24)
**When** the web UI or CLI is used
**Then** progressive hints show slightly more verbose output with inline guidance
**And** first-run init explains each step (scanning, conventions, building knowledge store)
**And** first `fam plan` includes brief orientation about the spec review process
**And** hints fade after approximately 5 sessions

**Given** notifications and onboarding are implemented
**When** tests run
**Then** notification provider detection and dispatch are tested via Mox (Notifications behaviour)
**And** progressive hint display and fade logic are tested
**And** `fam watch` terminal formatting is tested at 80 columns
**And** near-100% coverage on notification and onboarding modules

---

**Epic 7 Summary:** 9 stories (7.1a, 7.1b, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8), covering FR71-FR77, FR79 plus UX-DR1-DR27. All 8 FRs and 27 UX-DRs addressed. Story 7.2 (LiveView test infrastructure) is intentionally positioned early — all subsequent stories use its test helpers.

## Epic 8: Workflow & Role Configuration

User can customize agent behavior through markdown workflow and role definitions, add language support via configuration files, and manage interactive workflow session suspension and resumption.

### Story 8.1: Workflow & Role File Management

As a user,
I want to create and customize workflow and role definitions as simple markdown files,
So that I can tailor agent behavior without modifying system code.

**Acceptance Criteria:**

**Given** the `.familiar/workflows/` directory exists
**When** the user creates, edits, or deletes a workflow markdown file (FR65)
**Then** the system recognizes the change on next load
**And** workflow files define: trigger command, sequential pipeline steps, step mode (interactive/autonomous), and step-specific instructions

**Given** the `.familiar/roles/` directory exists
**When** the user creates, edits, or deletes a role markdown file (FR66)
**Then** the system recognizes the change on next load
**And** role files define: agent behavior, model selection, available tools, and system prompt (body of the file)

**Given** a workflow or role file is loaded
**When** validation runs (FR67)
**Then** valid files are loaded successfully
**And** invalid files produce clear, specific error messages (e.g., "Workflow 'feature-planning.md': missing required field 'trigger'")
**And** invalid files do not crash the system — they are skipped with the error reported

**Given** init completes for a new project
**When** the `.familiar/` directory is created
**Then** default MVP workflows (installed during init in Story 1.4) are recognized: feature-planning (`fam plan`), feature-implementation (`fam do`), task-fix (`fam fix`)
**And** default MVP roles (installed during init in Story 1.4) are recognized: analyst (interactive planning/fix), coder (autonomous implementation), reviewer (autonomous validation/knowledge extraction)
**And** users can create additional custom workflows and roles alongside the defaults
**And** each role has one trigger per workflow, no overrides or inheritance

**Given** workflow and role management is implemented
**When** unit tests run
**Then** file loading, validation (valid and invalid), and default installation are tested
**And** YAML frontmatter parsing for role/workflow metadata is tested
**And** near-100% coverage on workflow and role management modules

### Story 8.2: Interactive Session Management & Language Extensibility

As a user,
I want interactive workflow steps to handle idle timeouts gracefully and to add new language support without code changes,
So that suspended conversations can resume and the system works with any programming language.

**Acceptance Criteria:**

**Given** an interactive workflow step is in progress (e.g., planning conversation)
**When** the user goes idle past the configured timeout (FR68) — default 30 minutes, configurable in `.familiar/config.toml` under `[planning] idle_timeout_minutes`
**Then** the session is suspended (not terminated)
**And** the user can resume later via `fam plan --resume` or equivalent
**And** all conversation state is preserved in the `planning_messages` table

**Given** the user wants to add support for a new language (e.g., Python, Rust)
**When** they create a TOML configuration file in `.familiar/` (FR69)
**Then** the system loads the language config without requiring any Elixir code changes
**And** the config defines: test_command, build_command, lint_command, dep_file, skip_patterns, source_extensions
**And** the new language is available for init scan, validation, and convention discovery

**Given** an invalid language config is provided
**When** the system loads it
**Then** validation produces a clear error message identifying the issue
**And** the system falls back to existing valid configs

**Given** session management and language extensibility are implemented
**When** unit tests run
**Then** idle timeout detection and session suspension/resumption are tested with Clock mock
**And** language config loading, validation, and fallback are tested
**And** near-100% coverage on session management and language config modules

---

**Epic 8 Summary:** 2 stories, covering FR65-FR69. All 5 FRs addressed.
