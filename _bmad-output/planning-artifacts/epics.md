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
- **[Addendum 2026-04-03] Multi-agent orchestration promoted to MVP scope.** Single generic `AgentProcess` GenServer for all agents. All differentiation via user-editable role/skill markdown files. Project manager is an agent with its own role file. Parallel execution with configurable concurrency (default 3). See Architecture Addendum for full details.
- **[Addendum 2026-04-03] Role & skill file system.** Three-tier model: Role (markdown) → Skills (markdown) → Tools (Elixir registry). `Familiar.Roles` context loads/validates files at runtime. Inline prompts in `librarian.ex` and `prompt_assembly.ex` migrated to `.familiar/roles/`. FR65-FR67 partially addressed in new Epic 4.5, remainder in Epic 8.
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
FR65: Epic 4.5 — Create/edit/delete workflow definitions (foundation moved from Epic 8 per addendum 2026-04-03)
FR66: Epic 4.5 — Create/edit/delete role definitions (foundation moved from Epic 8 per addendum 2026-04-03)
FR67: Epic 4.5 — Validate workflow/role files on load (foundation moved from Epic 8 per addendum 2026-04-03)
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

### Architectural Reframing (Addendum 2026-04-03)
Familiar is a **multi-agent harness** with an extension system and opinionated default workflows, roles, and skills. The Elixir code provides the agentic execution environment (AgentProcess, tool registry, workflow runner, extension API, lifecycle hooks). The Knowledge Store and Safety enforcement are **default extensions**, not hard-coded harness features. All agent behavior is defined in user-editable markdown files. **Planning is not a special system — it is a workflow executed by agents.**

### Epic 4.5: Role & Skill File System Foundation
User-editable markdown files define all agent behavior. `Familiar.Roles` context loads/validates role and skill files at runtime. Default files installed during init.
**FRs covered:** FR65 (partial), FR66 (partial), FR67

### Epic 5: Agent Harness (rewritten 2026-04-03)
10 stories. Extension API with lifecycle hooks (alter + event). Tool registry. Single AgentProcess GenServer. Prompt assembly. File watcher (core). Safety extension. Knowledge Store extension. Workflow runner. File transactions. Integration test. See full breakdown below.

### Phase 3 Placeholders (deferred — vision clarifies as work commences)
- **Epic 6:** Default workflows & CLI integration — ship `feature-planning.md`, `feature-implementation.md`, `task-fix.md`, wire CLI commands
- **Epic 7:** Web UI extension — LiveView for activity observation, knowledge browsing, workflow interaction. Optional — headless Familiar is valid.
- **Epic 8:** CLI management & session handling — `fam roles/skills/workflows/extensions`, session timeout/resume

### Execution Order
```
Phase 1 (done): Epic 1, Epic 2, Epic 3 (stories 3-1 through 3-4)
Phase 2 — Agent Harness: Epic 4.5 (2 stories) → Epic 5 (10 stories)
Phase 3 — Workflows & UI: Epic 6, Epic 7, Epic 8 (stories TBD)
Post-MVP: Epic 4 (structured task management)
```

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

## Epic 4: Task Management (Post-MVP)

**[Addendum 2026-04-03] Moved to post-MVP.** The structured Ecto work hierarchy is a convenience upgrade, not a foundation. For MVP, agents track tasks in markdown files in `.familiar/tasks/` using `read_file`/`write_file`. The PM agent manages work the same way a human PM would — by reading and writing task files. When scale warrants it (post-MVP), this epic adds structured tracking with state machine enforcement, dependency resolution, and `fam tasks` CLI.

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

**Epic 4 Summary:** 4 stories (4.1a, 4.1b, 4.2, 4.3), covering FR32-FR37. All 6 FRs addressed. **[Addendum 2026-04-03] Post-MVP.** Agents use markdown task files for MVP.

## Epic 4.5: Role & Skill File System (2 stories)

User-editable markdown files in `.familiar/roles/` and `.familiar/skills/` define all agent behavior. The `Familiar.Roles` context loads, validates, and provides role/skill data at runtime. Default files installed during init. This is the prerequisite for Epic 5 — AgentProcess loads roles from these files.

**FRs covered:** FR65 (partial — file loading, not CLI CRUD), FR66 (partial — file loading, not CLI CRUD), FR67 (validation on load)

**Note:** Story 4.5-3 (Inline Prompt Migration) was completed as part of Story 4.5-0 (Planning Code Cleanup). The planning modules containing inline prompts were deleted entirely. Only 2 stories remain.

### Story 4.5-1: Roles Context & File Loading

As a user,
I want agent roles and skills defined as markdown files that the system loads at runtime,
So that I can customize agent behavior by editing files without touching code.

**Acceptance Criteria:**

**Given** role markdown files exist in `.familiar/roles/`
**When** the system loads a role
**Then** YAML frontmatter is parsed for metadata: name, description, model, lifecycle, skills list
**And** the markdown body (below frontmatter) is the system prompt
**And** `Roles.load_role("coder")` returns `{:ok, %Role{name, description, model, lifecycle, skills, system_prompt}}`
**And** `Roles.list_roles()` returns all valid roles found in the directory
**And** missing role returns `{:error, {:role_not_found, %{name: ...}}}`

**Given** skill markdown files exist in `.familiar/skills/`
**When** the system loads a skill
**Then** YAML frontmatter is parsed for metadata: name, description, tools list, constraints map
**And** the markdown body is the skill instructions (appended to prompt when skill is active)
**And** `Roles.load_skill("implement")` returns `{:ok, %Skill{name, description, tools, constraints, instructions}}`
**And** `Roles.list_skills()` returns all valid skills found in the directory

**Given** a role or skill file is loaded
**When** validation runs (FR67)
**Then** valid files load successfully
**And** invalid files produce clear, specific error messages (e.g., "Role 'my-role': missing required field 'skills'", "Role 'my-role' references skill 'foo' which does not exist in .familiar/skills/")
**And** invalid files do not crash the system — they are skipped with the error logged
**And** skills referencing tools not in the tool registry produce warnings (not errors — allows forward-declaration of custom tools)

**Given** the Roles context is implemented
**When** unit tests run
**Then** role loading, skill loading, listing, and validation are tested
**And** YAML frontmatter parsing for all metadata fields is tested
**And** error cases: missing file, malformed frontmatter, missing required fields, invalid skill references
**And** near-100% coverage on `Familiar.Roles` context

### Story 4.5-2: Default Role & Skill Files

As a user,
I want the system to install well-crafted default role and skill files during project initialization,
So that agents work out of the box while I can customize them later.

**Acceptance Criteria:**

**Given** `fam init` runs on a new project
**When** `.familiar/` directory is created
**Then** `.familiar/roles/` contains MVP role files with proper YAML frontmatter:
  - `analyst.md` — interactive planning conversation agent
  - `coder.md` — autonomous code implementation agent
  - `reviewer.md` — autonomous code review and knowledge extraction agent
  - `librarian.md` — multi-hop knowledge retrieval and summarization agent
  - `archivist.md` — post-task knowledge capture agent
  - `project-manager.md` — batch orchestration, worker coordination, progress summarization agent
**And** `.familiar/skills/` contains MVP skill files with proper YAML frontmatter and tool references
**And** each role file body contains the full system prompt (not stubs)
**And** `Knowledge.DefaultFiles.install/1` is updated to produce the new format

**Given** default files already exist (re-init or upgrade)
**When** `fam init` runs
**Then** existing role/skill files are NOT overwritten (user edits preserved)

**Given** default files are installed
**When** unit tests run
**Then** all installed role files pass `Roles.validate_role/1`
**And** all installed skill files pass `Roles.validate_skill/1`
**And** the librarian role's system prompt contains the search refinement and summarization instructions currently inline in `librarian.ex`
**And** the analyst role's system prompt contains the planning conversation instructions currently in `prompt_assembly.ex`

---

**Epic 4.5 Summary:** 2 stories (4.5-1, 4.5-2), covering FR65 (partial), FR66 (partial), FR67. Story 4.5-3 completed during planning code cleanup (Story 4.5-0).

## Epic 5: Agent Harness (10 stories — rewritten 2026-04-03)

The core agentic execution environment. A single generic `AgentProcess` GenServer executes any agent role defined in markdown. An extension API (`Familiar.Extension` behaviour) with lifecycle hooks (alter pipeline for veto, event hooks via PubSub) allows extensions to register tools and react to lifecycle events. The Knowledge Store and Safety enforcement are default extensions. A file watcher keeps context fresh. A workflow runner sequences agents through markdown-defined workflows. **This is the core reason BEAM/OTP was chosen.**

**Design principle:** Build only the harness infrastructure. All workflow opinions (what agents do, how planning works, what specs look like) belong in markdown files, not Elixir code. Near-term stories get full detail. Later stories stay as outlines — vision clarifies as work commences.

### Story 5.1: Extension API & Lifecycle Hooks

As a developer building the harness,
I want an extension system with lifecycle hooks so that capabilities (tools, safety, knowledge) are pluggable,
So that the harness core stays thin and extensions can react to agent lifecycle events.

**Scope:** `Familiar.Extension` behaviour (name, tools, hooks, child_spec, init). `Familiar.Hooks` GenServer — alter pipeline (reduce_while + try/rescue + timeout + circuit breaker) and event dispatch (subscribes Activity PubSub on behalf of extensions). Extension loader in `Application.start/2` reads config, starts child specs, registers tools and hooks. Tests: alter pipeline ordering, veto, skip-on-error, timeout, circuit breaker. Event dispatch isolation.

### Story 5.2: Tool Registry

As a developer building the harness,
I want a central registry mapping tool names to Elixir implementations that dispatches through the hooks pipeline,
So that extensions can register tools and every tool call flows through safety checks.

**Scope:** `Familiar.Execution.ToolRegistry` — GenServer or ETS-backed registry. `register/3` (name, function, description). `dispatch/3` (name, args, context) runs `before_tool_call` alter hook → executes tool → broadcasts `after_tool_call` event. Core built-in tools: `read_file`, `write_file`, `delete_file`, `list_files`, `run_command`, `spawn_agent`, `monitor_agents`, `broadcast_status`, `signal_ready`. Tool descriptions exported for LLM tool-call schemas.

### Story 5.3: AgentProcess & Tool Call Loop

As a developer building the harness,
I want a single generic GenServer that loads any role from markdown and runs an LLM-driven tool call loop,
So that all agents use one well-tested executor regardless of role.

**Scope:** `Familiar.Execution.AgentProcess` GenServer under `Familiar.AgentSupervisor` (DynamicSupervisor). `start_link(role: name, task: data, parent: pid)`. On init: load role via `Roles.load_role/1`, resolve tools from skills. Tool-call loop via `handle_continue`/`handle_info`: assemble prompt → call LLM → parse tool calls → dispatch via ToolRegistry → append results → repeat. Status reporting to parent via `GenServer.cast`. Safety limits: max tool calls (~100), per-task timeout. Full LLM response logging. Activity event broadcasting.

### Story 5.4: Prompt Assembly

As a developer building the harness,
I want a pure function that assembles role prompts, skill instructions, and context into LLM messages,
So that prompt construction is testable, provider-agnostic, and manages token budgets.

**Scope:** Pure function module. Inputs: role system prompt (from file) + skill instructions (from files) + context block + conversation history + provider config. Output: message list for `Providers.chat/2` + truncation metadata. Token budget management: measure each component, prioritize most relevant, truncation warnings. Provider-specific formatting. No hard-coded prompt content. 100% coverage required (thesis-critical).

### Story 5.5: File Watcher

As a developer building the harness,
I want a core GenServer that watches the project directory for changes and broadcasts events,
So that extensions can react to file modifications in real time.

**Scope:** GenServer using `file_system` hex package (inotify/fsevents). Debounces rapid changes (500ms settle per file). Broadcasts `on_file_changed`, `on_file_created`, `on_file_deleted` via `Familiar.Activity`. Configurable ignore list from `.familiar/config.toml` `[watcher]` section (defaults: `.git/`, `_build/`, `deps/`, `node_modules/`, `.familiar/` internals). Core process in supervision tree — not an extension.

### Story 5.6: Safety Extension

As a developer building the harness,
I want a default extension that vetoes dangerous tool calls via the alter hook pipeline,
So that agents cannot escape the project directory, commit without approval, or execute arbitrary commands.

**Scope:** Implements `Familiar.Extension`. Registers `before_tool_call` alter hook at priority 1. Validates: path within project directory (canonical after symlink resolution), no `.git/` writes, shell commands restricted to allow-list, delete only own-task files, secret detection. Configurable via `.familiar/config.toml` `[safety]` section. Returns `{:halt, reason}` to veto. Tested with both allowed and rejected cases for every constraint.

### Story 5.7: Knowledge Store Extension

As a developer building the harness,
I want the existing Knowledge Store refactored to implement the Extension behaviour,
So that it registers tools and hooks like any other extension and can be replaced or augmented.

**Scope:** Wraps existing `Familiar.Knowledge` context in `Familiar.Extensions.KnowledgeStore` implementing `Familiar.Extension`. Registers `search_context` and `store_context` tools. Registers event hooks: `on_agent_complete` (post-task knowledge capture via hygiene loop), `on_file_changed` (update/invalidate entries). Supervision child spec for embedding worker pool. Existing Knowledge modules, schemas, and tests preserved — this story adds the extension wrapper.

### Story 5.8: Workflow Runner

As a developer building the harness,
I want a module that reads workflow markdown definitions and sequences agents through steps,
So that planning, implementation, fix, and custom workflows all execute through one mechanism.

**Scope:** `Familiar.Execution.WorkflowRunner`. Reads workflow `.md` files (YAML frontmatter with steps list). For each step: spawns AgentProcess with step's role, passes accumulated context from previous steps. Interactive mode: multi-turn conversation via Channel. Autonomous mode: run to completion. Phase transitions via `signal_ready` tool call. `parallel: true` dispatches concurrent agents. Context accumulation: `%{previous_steps: [%{step: name, output: result}]}`. This is what makes `fam plan`, `fam do`, and `fam fix` all work.

### Story 5.9: File Transaction Module

As a developer building the harness,
I want crash-safe file writes with rollback capability,
So that agent file operations are atomic and parallel agents don't corrupt each other's work.

**Scope:** SQLite-backed intent logging. Strict sequence: log intent → write file → log completion. Pre-write stat check by content hash (FR56b). Idempotent rollback. File claim registration: `Files.claimed_files/0` for PM to detect conflicts. `.fam-pending` for conflict files. 100% coverage + StreamData property tests.

### Story 5.10: Harness Integration Test

As a developer,
I want an end-to-end test validating the complete harness,
So that extensions, agents, tools, hooks, and workflows work as a coherent system.

**Scope:** Golden path: load extensions → register tools/hooks → start workflow → spawn AgentProcess → tool-call loop with mocked LLM → file writes via transaction module → safety extension vetoes out-of-scope write → knowledge extension captures results → workflow completes. Failure paths: agent crash, tool timeout, file conflict. Real SQLite via Ecto sandbox; LLM/Shell/FileSystem mocked via Mox.

---

**Epic 5 Summary:** 10 stories. Builds the complete agent harness: extension API, tool registry, generic agent executor, prompt assembly, file watcher, safety extension, knowledge store extension, workflow runner, file transactions, and integration test.

## Epic 6: Default Workflows & CLI Integration (Phase 3 — placeholder)

**Deferred until Epic 5 is complete.** Stories will be defined based on what the workflow runner actually supports.

Define and test the default workflow markdown files that ship with Familiar: `feature-planning.md`, `feature-implementation.md`, `task-fix.md`. Wire CLI commands (`fam plan`, `fam do`, `fam fix`) to dispatch workflows through the runner. This is where the "opinionated defaults" come to life — the harness is generic, the workflows are the product. Includes default role and skill file refinement based on real execution experience.

Recovery (`fam fix`) is a workflow, not a separate system — the analyst agent opens a conversation pre-loaded with failure context. Self-repair (autonomous retry on stale context) is PM role behavior defined in the project-manager role file.

---

## Epic 7: Web UI Extension (Phase 3 — placeholder)

**Deferred until Epic 5 is complete.** The Web UI is an extension implementing `Familiar.Extension`.

LiveView interface for observing agent activity, browsing the knowledge store, and interacting with workflows. Subscribes to Activity PubSub for real-time updates. A headless Familiar (CLI-only) is valid — the web UI is optional. Scope will be refined based on what the harness and workflow runner actually expose. Keyboard-first, zero-chrome design per UX spec.

---

## Epic 8: CLI Management & Session Handling (Phase 3 — placeholder)

**[Superseded 2026-04-10]** This epic's scope was delivered as **Epic 7** after a reorder that moved CLI management earlier. Epic 7 shipped `fam roles/skills/workflows/extensions/sessions/validate`. Interactive session timeout/resume was delivered in Story 7.5-6. Language extensibility is already in the config.toml + `Generator.detect_project_language/1`. **See Epic 8 below for the current MCP Support content.**

---

**Phase 3 note (original):** Epics 6-8 were intentionally light. Detailed story breakdowns were written as work commenced, and the epic numbering was reordered as scope clarified.

---

## Story 7.5-8: Project-Dir Resolution & Entry-Point Hardening

*(Added 2026-04-10 to the in-progress Epic 7.5. Epic 7.5 itself has no formal writeup — see sprint-status.yaml and individual `7.5-*.md` artifacts for prior stories. This is an immediate priority: the pain already exists for multiple processes that need to know the project directory; pulled forward from Epic 11 Story 11-4 where it was originally scoped.)*

As a Familiar user whose daemon, CLI, escript, and background jobs all need to agree on which directory is "the project",
I want a single explicit resolution path used by every entry point, with loud failure when it can't resolve,
So that processes spawned by editors, CI, launchd, systemd, or unfamiliar shells don't silently fall back to the wrong directory and corrupt state — and so that debugging "why is Familiar looking at `/tmp`?" takes seconds instead of hours.

**Why now:** Story 7.5-5 audited `File.cwd!/0` usage and routed most callers through `Familiar.Daemon.Paths.project_dir/0`. That closed the bulk of the obvious holes but left the *entry-point* question unsolved: when a process first starts (daemon boot, escript invocation, CLI command against a running daemon, `fam mcp serve` spawned by an editor, background job from a supervisor restart), what decides which project it belongs to? Today the answer is "whatever was in cwd at spawn time, unless `FAMILIAR_PROJECT_DIR` is set," with no walk-up, no validation that the result is a Familiar project, and inconsistent error messages across entry points. Epic 11 Story 11-4 exposed this pain for `fam mcp serve`, but the same pain already bites existing processes. Fix it once for everyone before MCP builds on top of it.

**Scope:**

*Audit and standardize.* Enumerate every entry point that resolves `project_dir`: (1) `fam` escript startup, (2) daemon `application.ex` boot, (3) each `fam` CLI command's pre-flight, (4) `Familiar.Execution.WorkflowRunner` resume path, (5) background jobs spawned from supervisors (embedding indexer, file watcher, knowledge store maintenance, drift check), (6) test helpers. For each, confirm it goes through `Paths.project_dir/0` — any that still call `File.cwd!/0` directly or read `FAMILIAR_PROJECT_DIR` directly get replaced.

*Single precedence chain in `Paths.resolve_project_dir/1`.* New function that accepts an optional explicit override and returns `{:ok, dir, source}` or `{:error, reason}`. Precedence:

1. **Explicit argument** (e.g. `--project-dir` flag value passed by CLI commands). Source = `:explicit`.
2. **`FAMILIAR_PROJECT_DIR` env var.** Source = `:env`.
3. **Cwd walk-up** — starting from `File.cwd!/0`, walk parent directories looking for a `.familiar/` subdir; stop at filesystem root or `$HOME`. Source = `{:walk_up, found_at}`. This is new behavior modeled on how `git` resolves the repo root. It is the single biggest QoL win in this story — `fam` commands become usable anywhere inside a project tree, not just at the root.
4. **Hard error** with `{:error, {:project_dir_unresolvable, %{cwd: ..., checked_env: true}}}`.

`Paths.project_dir/0` keeps its current signature but becomes a thin wrapper over `resolve_project_dir/1` that raises on error (for code paths that can't handle the error tuple gracefully). New `Paths.project_dir_or_error/0` for callers that can.

*Validation.* Whatever dir is resolved, confirm it contains a `.familiar/` subdirectory before returning success. If not, `{:error, {:not_a_familiar_project, %{path: resolved_dir, source: source}}}` — distinct from `:project_dir_unresolvable` so the error message can be specific ("I found a directory, but it isn't a Familiar project — run `fam init` or point elsewhere").

*Error messages.* Add `:project_dir_unresolvable` and `:not_a_familiar_project` to `Familiar.CLI.Output.error_message/2`. Both messages must include: (a) the directory that was checked, (b) whether `FAMILIAR_PROJECT_DIR` was set and what it contained, (c) a copy-pasteable fix showing both `--project-dir /path` and `FAMILIAR_PROJECT_DIR=/path fam <cmd>` syntax, (d) a one-line pointer to `fam where` for debugging.

*`fam where` command.* New subcommand that prints:

```
project_dir:  /home/user/code/myapp
source:       walk-up (found .familiar/ at /home/user/code/myapp)
cwd:          /home/user/code/myapp/lib/myapp
env:          FAMILIAR_PROJECT_DIR (unset)
familiar_dir: /home/user/code/myapp/.familiar  (exists)
config:       /home/user/code/myapp/.familiar/config.toml  (exists)
daemon:       running (pid 12345, socket /home/user/code/myapp/.familiar/daemon.sock)
```

`--json` emits the same as a data envelope. When resolution *fails*, `fam where` prints what it tried and exits with `:project_dir_unresolvable` — so the user can run it from a broken shell to see exactly what the precedence chain saw. This is the single most valuable debugging artifact this story ships.

*Tests.* Unit tests for `resolve_project_dir/1` covering all four precedence branches + both error cases. Integration-ish tests for `fam where` from (a) inside a project, (b) inside a subdirectory of a project, (c) outside any project, (d) with `FAMILIAR_PROJECT_DIR` set to a bogus path. Existing entry-point tests that touched `project_dir` get updated. Flake stress test per the zero-tolerance policy.

**Out of scope (explicitly):** Multi-project daemon support (running one daemon process against several projects) — out. Per-user config dir (`$XDG_CONFIG_HOME/familiar`) — out. Changing `.familiar/` to a dotfile search pattern (`.familiar` or `familiar.toml` in the way some tools support either) — out.

**Follow-on cleanup in Epic 11 Story 11-4:** With `resolve_project_dir/1` in place, `fam mcp serve` just calls it with the `--project-dir` value and gets the full precedence + walk-up + error messages for free. Story 11-4 scope shrinks to "call the existing resolver; surface the resulting error in the editor-config format."

---

## Epic 7.6: Safety Removal & Sandboxing Posture (3 stories — drafted 2026-04-10)

Remove the `Familiar.Extensions.Safety` extension and reframe execution safety honestly: Familiar runs LLM-generated tool calls including file writes and shell commands, the LLM is an untrusted actor, and the only meaningful boundary is the OS sandbox the user chooses to run Familiar inside. This epic takes the system from "we have a safety module that pattern-matches dangerous tool names" (false confidence — an LLM can trivially call `sh` instead of `run_command`) to "we give you a container recipe and a clear warning."

**Why now:** Epic 8 (MCP Support) is about to expose Familiar's tools over a wire protocol to external editors *and* let Familiar invoke external MCP servers' tools. Both directions make the Safety extension's name-pattern approach even weaker — external tools with names like `github__delete_repository` or `postgres__execute_sql` don't match any built-in pattern, and editors calling into Familiar have no TTY for confirmation prompts. Better to remove the theater before building a second wire that depends on it.

**Design principles:**
- **Container is the boundary.** The honest security story is OS-level isolation, not runtime pattern matching. Prior art: Pi (which Familiar's architecture already borrows from) took the same stance.
- **Warn prominently, don't police softly.** The user should see a sandboxing warning during `fam init`, in `fam --help`, and at the top of the README. The warning should name the risk explicitly (LLM-generated shell commands, file writes) and link to `docs/sandboxing.md`.
- **Pure subtraction for code.** No replacement safety layer. The `Familiar.Extension` behaviour stays (other extensions still use it); the `before_tool_call` / `after_tool_call` hook points stay (useful for logging, metrics, knowledge retrieval); the ability to return `{:halt, reason}` from a hook stays (still a valid extension capability, just nobody ships a built-in extension that uses it).
- **Keep what isn't execution safety.** Secret filtering in the knowledge store (Story 2-6) is *data hygiene*, not execution safety — it prevents API keys from landing in embeddings, which is still worth doing. Stays.
- **`--read-only` in `fam mcp serve` reframes.** Instead of "Safety vetoes write tools," it becomes "write tools aren't registered with the MCP dispatcher." Same outcome, honest framing. Implementation detail carried into Epic 8.

### Story 7.6-1: Remove Safety Extension

As a Familiar maintainer,
I want the `Familiar.Extensions.Safety` module and every integration point deleted,
So that the codebase stops providing a false-confidence safety layer that an adversarial LLM can trivially bypass.

**Scope:** Delete `familiar/lib/familiar/extensions/safety.ex` and `familiar/test/familiar/extensions/safety_test.exs`. Remove Safety references from `execution/hooks.ex`, `execution/tools.ex`, `execution/agent_process.ex`, `execution/tool_registry.ex`, `execution/extension.ex`, `extensions/extensions.ex`, `knowledge/default_files.ex`, `knowledge/backup.ex`. Remove Safety from the default extensions list in `Familiar.Extensions`. Update affected tests (`harness_integration_test.exs`, `knowledge_integration_test.exs`, `hooks_test.exs`, `default_files_test.exs`, `path_resolution_defaults_test.exs`, `workflows_extensions_test.exs`, `tool_registry_test.exs`, `agent_process_test.exs`) — either delete Safety-specific test cases or strip Safety setup from shared fixtures. Remove any Safety-specific error atoms from `Familiar.CLI.Output.error_message/2`. Keep the `Familiar.Extension` behaviour, the `before_tool_call` / `after_tool_call` hook points, and the `{:halt, reason}` return contract fully intact. Verify: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`, `mix dialyzer` all clean. Stress-test any touched test files 50x per the flaky-test policy.

### Story 7.6-2: Sandboxing Warning + Reference Container

As a Familiar user,
I want a prominent warning about execution risk plus a copy-pasteable container recipe,
So that I understand Familiar is running untrusted LLM output on my machine and I know exactly how to sandbox it.

**Scope:** Three artifacts.

*Warning surface.* Add a clearly-marked security notice to (1) `README.md` top section above installation, (2) `fam --help` main usage output (one line pointing at `docs/sandboxing.md` and the dedicated `fam security` subcommand below), (3) the success output of `fam init` (a boxed notice after the "Project initialized" line), (4) a new `fam security` subcommand that prints the full warning + sandboxing recommendations to stdout for users who want to re-read it later. Warning text must explicitly name: LLM generates tool calls, tool calls include `write_file` / `delete_file` / `run_command`, the LLM is an untrusted actor, running outside a container puts the user's host filesystem and network at risk.

*Reference Dockerfile.* Restore a minimal `familiar/Dockerfile` (the one deleted in Story 7.5-3). Multi-stage build: `hexpm/elixir` builder → `debian:bookworm-slim` runtime. Installs the escript from Story 7.5-3 to `/usr/local/bin/fam`. Runs as non-root user. Mounts `/workspace` as the project dir with `FAMILIAR_PROJECT_DIR=/workspace`. `CMD ["fam", "help"]` as default. Ships alongside a `familiar/docker-compose.yml` that wires the workspace mount and an LLM provider env var. The README's quick-start becomes `docker compose run --rm familiar init` rather than a native install.

*Sandboxing doc.* New `familiar/docs/sandboxing.md` covering: (1) why we don't ship runtime safety — the honest "LLM-generated commands + name-pattern matching = theater" explanation, (2) recommended Docker invocation with `--network`, `--read-only`, and `--cap-drop` flags for users who want more isolation than docker-compose defaults, (3) recommended Podman invocation (users wary of Docker daemon), (4) how to run Familiar inside an ephemeral VM (Firecracker, QEMU) for paranoid workflows, (5) a "what a sandbox does NOT protect you from" section (data exfiltration via LLM provider API calls, prompt injection that steals secrets from env vars the container has, etc.) — because we're being honest now.

### Story 7.6-3: Planning Docs & Epic 5/8 Reframing

As a Familiar maintainer,
I want the planning artifacts to reflect the Safety removal and the new sandboxing posture,
So that future story work and epic drafts don't accidentally re-introduce the Safety concept or depend on it.

**Scope:** Update `_bmad-output/planning-artifacts/architecture.md` — remove Safety from the extension list, replace the "runtime safety" section with a "sandboxing posture" section pointing at `docs/sandboxing.md`, update any tool-call sequence diagrams that show Safety as a pipeline step. Update `_bmad-output/planning-artifacts/epics.md` — mark Epic 5 Story 5-6 (Safety Extension) with a "**[Superseded 2026-04-10 by Epic 7.6-1]**" note and update Epic 5 summary to mention Safety was removed. (Epic 8 and Epic 11, drafted 2026-04-10 after this epic, already reflect the post-Safety posture — no retro-edits needed on them.) Do **not** rewrite historical implementation artifacts (Story 5-6 artifact, Epic 5 retro, 2-6 secret filtering) — they're historical records of work done and should read as "this existed and was later removed." Update `_bmad-output/planning-artifacts/prd-validation-report.md` and `implementation-readiness-report-2026-04-01.md` only if they contain claims that actively contradict the new posture (stale references are fine; active contradictions need footnotes). Add an entry to the project memory (`project_sandboxing_posture.md`) recording the decision and its rationale so future conversations don't accidentally propose adding Safety back.

---

**Epic 7.6 Summary:** 3 stories. Removes the Safety extension in pure subtraction, replaces it with a prominent warning surface and a reference Docker container, and updates planning artifacts so Epic 8 (and everything after) builds on the honest "container is the boundary" stance instead of the false-confidence safety pattern matcher. No runtime safety replacement — the Extension behaviour and hook points stay, they're just not used to police tool calls by any built-in extension. Post-epic: Epic 8 friction items that depended on Safety (confirmation in serve mode, external MCP tool vetoing) collapse; the surviving friction items get folded into Epic 8 story scope.

---

## Epic 8: MCP Client Support (5 stories — drafted 2026-04-10, split 2026-04-10)

Let Familiar agents call external MCP servers (GitHub, Linear, Postgres, Playwright, filesystem, etc.) as first-class tools. Each configured MCP server shows up in Familiar as an extension whose tools are registered in the existing `ToolRegistry` and made available to every agent alongside built-in tools.

**Scope split note:** This epic was originally drafted as "MCP Support" covering both client (Familiar uses external MCP servers) *and* server (Familiar exposes its tools to editors over stdio). On 2026-04-10 the server direction was moved post-MVP to Epic 11 on the grounds that (a) letting users augment Familiar's agent capabilities with the huge and growing MCP ecosystem is much higher-leverage than the opposite direction, and (b) anyone who wants Claude Code or Cursor to drive Familiar can point their editor at the `fam` CLI documentation — the CLI is already fully functional and JSON-output-capable, so no MCP server plumbing is required to get that integration.

**Why now:** Epic 7.5 finished the provider story, so Familiar now has real LLMs and actual knowledge retrieval. The next big capability unlock is removing the "you need to write an Elixir extension for every integration" ceiling — MCP turns every MCP-spec-compliant server on GitHub, npm, or PyPI into a drop-in tool provider for Familiar agents, with zero code changes per integration.

**Design principles:**
- **Reuse `ToolRegistry` and `Extensions`.** MCP is a transport + schema — the agent harness doesn't care. Every external MCP tool registers through `ToolRegistry.register/4`, so the LLM sees them exactly like built-in tools and existing hooks (logging, knowledge retrieval, etc.) fire unchanged.
- **Subprocess per server over stdio.** Familiar launches each MCP server as a subprocess via `Port.open/2` and speaks line-delimited JSON-RPC over pipes. That's how every editor-hosted MCP client works today and covers every MCP server shipped on npm. HTTP/SSE transport for remote MCP servers is post-MVP.
- **Tools first, resources later.** The MCP spec has four capabilities: tools, resources, prompts, sampling. The client MVP only implements `tools/list` + `tools/call`. Consuming external *resources* (read-only data sources) is a natural follow-up but not required to hit the main goal of "more tools."
- **Match Claude Code's MCP management UX.** Users expect `fam mcp add/list/get/remove/enable/disable` to mirror `claude mcp add/list/get/remove` so muscle memory transfers. The runtime source of truth is an `mcp_servers` SQLite table; `.familiar/config.toml` `[[mcp.servers]]` entries are a *second* source merged in at boot for checked-in project servers. CLI mutations only touch the DB, so no file-watcher or config-reload plumbing is needed — the daemon simply restarts the affected `Familiar.MCP.Client` child after a DB write.
- **Container is the boundary.** Per Epic 7.6, Familiar has no runtime safety layer — the honest sandbox is the OS. External MCP servers run in the same container as Familiar itself (not in nested sandboxes), so they inherit whatever filesystem and network access the user gave Familiar. The sandboxing docs should explicitly cover this.
- **No new dependencies unless required.** `Jason` covers the JSON-RPC envelope; Erlang's `Port` covers the subprocess plumbing. No new hex packages expected.

### Story 8-1: MCP Protocol Codec & Dispatcher

As a developer building MCP support,
I want a pure module that encodes and decodes JSON-RPC 2.0 envelopes plus a method dispatcher,
So that the client GenServer has a well-tested wire format with no coupling to transport details, and the same codec can be reused by Epic 11 if the server direction ships later.

**Scope:** `Familiar.MCP.Protocol` — `encode_request/3`, `encode_response/3`, `encode_error/3`, `decode/1` (returns `{:request, id, method, params}` / `{:response, id, result}` / `{:error, id, code, message}` / `{:notification, method, params}`). Standard JSON-RPC error codes (`-32700 parse error`, `-32600 invalid request`, `-32601 method not found`, `-32602 invalid params`, `-32603 internal error`). `Familiar.MCP.Dispatcher` — method → handler routing table, each handler is `(params, context) -> {:ok, result} | {:error, code, message}`. 100% coverage; property tests for encode/decode round-trip. Pure module, no GenServer, no IO — transport-agnostic.

### Story 8-2: MCP Client Connection

As an agent author,
I want Familiar to launch external MCP server subprocesses and register their tools in `ToolRegistry`,
So that my agents can call GitHub, Postgres, Playwright, and other MCP servers without me writing a new Elixir extension per integration.

**Scope:** `Familiar.MCP.Client` — per-connection GenServer supervised under `Familiar.MCP.ClientSupervisor` (DynamicSupervisor). `start_link(name, command, args, env)` spawns the external server via `Port.open/2` with line framing, performs the MCP `initialize` handshake, calls `tools/list`, and registers each discovered tool in `ToolRegistry` with name `"<namespace>__<tool_name>"` so tools from different MCP servers don't collide. Tool call path: the registered function in `ToolRegistry` translates Familiar args → JSON-RPC `tools/call` → waits for response → translates result back. Env values are expanded through `Familiar.Config.expand_env/1` at launch time so `${VAR}` references resolve to process env. Crash-safe: if the external process dies, the client GenServer cleans up its registered tools and the supervisor restarts it (with an exponential backoff on repeated failures). Connect/call timeouts configurable per-server.

**Friction items baked into scope** (from design review):
- **Async startup.** Slow-to-initialize MCP servers (ones that load models, establish cloud auth, etc.) must not block daemon boot. The client GenServer returns from `init/1` immediately and does the handshake + `tools/list` in a `handle_continue/2`. Until the handshake completes, its state is `:connecting`; `ToolRegistry` calls to an unregistered tool return `{:error, :tool_not_yet_available}` with a helpful message.
- **Explicit status state machine.** `:connecting`, `:connected`, `:handshake_failed`, `:crashed`, `:disabled`, `:unreachable` — no lumping into a single "error" bucket. Each state has a reason string surfaced by `fam mcp list` / `fam mcp get`.
- **Reserved tool-name prefixes.** Reject server names that would collide with built-in tools (check against `ToolRegistry.list/0` at server-creation time in Story 8-3), and reserve `fam_` as a prefix Familiar may use for future built-ins.
- **Graceful degradation on removal.** If an agent is mid-call when a server is removed, the in-flight call returns `{:error, :mcp_server_removed}` instead of crashing the agent process.

### Story 8-3: MCP Server Storage & Client Extension

As a Familiar user,
I want MCP server configurations stored durably so CLI-added servers persist across daemon restarts and `config.toml`-declared servers load automatically,
So that I can manage MCP servers the same way Claude Code does while still supporting checked-in project configs.

**Scope:** Two pieces.

*Storage layer.* New `mcp_servers` table migration: `name` (unique), `command`, `args_json`, `env_json`, `disabled` (bool), `read_only` (bool), timestamps. `Familiar.MCP.Servers` context module with `list/0`, `get/1`, `create/1`, `update/2`, `delete/1`, `enable/1`, `disable/1` functions returning `{:ok, server}` / `{:error, changeset | :not_found}`. Changeset validates name format (`^[a-z][a-z0-9_-]*$` so it's safe as a tool-name prefix), rejects names that collide with built-in `ToolRegistry` entries or the reserved `fam_` prefix, requires `command`, JSON-encodes `args` and `env`. Env values support `${VAR}` interpolation resolved at client-launch time (not at write time) so secrets aren't stored literally — **reuse the existing `Familiar.Config.expand_env/1` helper** at `familiar/lib/familiar/config.ex:265` (already used for provider `api_key` / `base_url` / `chat_model` / `embedding_model` settings). It's currently `defp`; promote it to `def` (or extract to a small `Familiar.Config.EnvExpander` module) as part of this story so `Familiar.MCP.Client` can call it without duplicating the regex. Document the `${VAR}` syntax in the changeset doc and `fam mcp add --help`.

*Client extension.* `Familiar.Extensions.MCPClient` implements `Familiar.Extension`. On init, builds its server list by merging two sources: (1) rows from `Familiar.MCP.Servers.list/0` (source = `:db`), (2) `[[mcp.servers]]` entries from `.familiar/config.toml` (source = `:config`). DB entries win on name collision; a warning is logged if a name appears in both. For each enabled entry, starts a `Familiar.MCP.Client` child under the extension's supervisor (Story 8-2). The extension exposes `reload_server/1` so the management CLI (Story 8-4) can trigger a single-server restart after a DB mutation without bouncing the whole extension. `fam extensions` output shows each connected MCP server with its source marker (`db` or `config`), status (from the Story 8-2 state machine), and discovered tool count. Configuration errors (missing command, unreachable server) log warnings and keep the extension alive with the bad server in an error state — they do not crash boot.

*`--read-only` semantics.* The `read_only` flag on an `mcp_servers` row is a **capability filter**, not a safety veto. When it's set, the client registers only the tools whose names match a read-only name pattern (default allowlist: `list_*`, `get_*`, `read_*`, `search_*`, `query_*`, `describe_*`, `show_*`, `fetch_*`); all other discovered tools are simply not added to `ToolRegistry` for that server. The pattern list is configurable per server via an optional `read_only_patterns` field in Story 8-4's `add-json`. This is honest: "we don't register write tools" is a true statement; "we veto write tools at runtime" would be the Safety theater that Epic 7.6 removed.

### Story 8-4: `fam mcp` Management CLI

As a Familiar user,
I want `fam mcp add/list/get/remove/enable/disable` subcommands that mirror Claude Code's MCP UX,
So that managing MCP servers feels identical across the two tools and doesn't require hand-editing TOML for every change.

**Scope:** New `fam mcp` command group with management subcommands, all writing to the `mcp_servers` table via `Familiar.MCP.Servers` and triggering a live reload via `Familiar.Extensions.MCPClient.reload_server/1`.

- `fam mcp add <name> <command> [args...] [--env KEY=VALUE]... [--read-only] [--disabled]` — inserts a new row. Refuses if name already exists in DB; warns and refuses if name collides with a `config.toml` entry. Prints the resulting config in the same format as `get`. Supports repeated `--env` flags for multiple vars. **Literal-secret warning:** if any `--env` value does not contain `${VAR}` / `$VAR` (i.e. the user pasted a raw token), emit a prominent warning to stderr: `"Note: <KEY> was stored as a literal value. To reference an environment variable instead, use --env <KEY>='${<KEY>}'. The literal value is now in the .familiar database and your shell history."` Still performs the insert (the user may have reasons) but makes sure they know.
- `fam mcp add <name> <command> [args...] --validate` — optional flag that does a one-shot dry-run connect after insert: launches the subprocess, runs the handshake, calls `tools/list`, prints the discovered tool count, then tears down. If the dry-run fails, prints the error and asks `"Save anyway? [y/N]"` (interactive) or returns a non-zero exit (non-interactive / `--json`). Off by default so CI scripts aren't surprised, but prominently documented as recommended.
- `fam mcp add-json <name> <json>` — same as `add` but takes a JSON blob for complex configs (matches `claude mcp add-json`). JSON shape: `{"command": "...", "args": [...], "env": {...}, "read_only": false, "disabled": false, "read_only_patterns": ["list_*", "get_*"]}`.
- `fam mcp list [--json]` — prints a table of all known servers (DB + config.toml merged view) with columns: `NAME`, `SOURCE` (db/config), `STATUS` (`connected` / `connecting` / `handshake_failed` / `crashed` / `disabled` / `unreachable`), `TOOLS` (count), `COMMAND` (truncated to 40 chars; full command shown by `get`). `--json` emits the standard `Familiar.CLI.Output` data envelope with non-truncated fields.
- `fam mcp get <name> [--json] [--show-env]` — prints full details for one server: command, full args, env keys (values redacted unless `--show-env`), source, status + reason, discovered tool names. Errors with `:mcp_server_not_found` if absent.
- `fam mcp remove <name>` — deletes a DB row and tears down the client child. If the name only exists in `config.toml`, errors with `:mcp_server_config_only` and tells the user to edit the TOML file directly (do NOT offer to edit it for them — that's out of scope and footgun-prone). Any in-flight tool calls to that server return `{:error, :mcp_server_removed}` (per Story 8-2 graceful-degradation note).
- `fam mcp enable <name>` / `fam mcp disable <name>` — flips the `disabled` flag on a DB row and live-reloads the client (enable triggers a fresh start, disable tears down). Config-sourced servers get the same `:mcp_server_config_only` error.

*Project-dir resolution.* All subcommands support `--project-dir` via the existing `Familiar.Daemon.Paths` plumbing. When the daemon is running, CLI mutations go through the daemon RPC so there's a single DB writer. When the daemon is not running, the CLI opens a short-lived Repo connection, performs the write, and exits — the next daemon boot picks up the change. This matches how other `fam` CLI mutation commands already work.

*Error envelopes.* New error atoms: `:mcp_server_not_found`, `:mcp_server_name_taken`, `:mcp_server_config_only`, `:mcp_server_invalid_name`, `:mcp_server_invalid_json`, `:mcp_server_reserved_prefix`. Each has a friendly message in `Familiar.CLI.Output.error_message/2`. Each command has CLI-level tests covering the happy path and at least two error paths.

*Post-MVP:* `fam mcp import-claude` that reads `~/.claude.json` and bulk-imports existing Claude Code server entries with a `--dry-run` preview. Big adoption win — users hate re-typing — but the epic can ship without it. Flagged here so future stories don't step on the naming.

### Story 8-5: MCP Client Integration Test

As a developer,
I want an end-to-end test that runs the MCP client against a scripted fake MCP server,
So that a regression in codec, client connection, tool registration, or management CLI shows up before release.

**Scope:** Spins up a scripted fake MCP server (either an Elixir `GenServer` pretending to be a subprocess via a paired `Port` shim, or a tiny standalone Elixir escript the test launches via `Port.open/2` to exercise the real subprocess path). Test flow:

1. Daemon boot with no MCP servers configured — extension starts clean.
2. `fam mcp add` a fake server — row lands in DB, `reload_server/1` starts the client, handshake completes, tools appear in `ToolRegistry`.
3. Agent calls one of the registered tools — request round-trips to the fake server, response lands back in the agent.
4. `fam mcp list` shows the server with status `:connected` and correct tool count.
5. `fam mcp disable` the server — client tears down, tools disappear from `ToolRegistry`, subsequent calls return `:tool_not_yet_available`.
6. `fam mcp enable` the server — client restarts, tools reappear.
7. `fam mcp remove` the server — row gone, tools gone, in-flight call (simulated) returns `:mcp_server_removed`.
8. `config.toml`-sourced server with same name as a DB server — warning logged, DB wins, `fam mcp list` shows both source markers via the merged view if the DB row is later removed.
9. Fake server crashes mid-handshake — status transitions to `:handshake_failed` with reason, subsequent `reload_server/1` retries cleanly.
10. Literal-secret warning fires when `fam mcp add --env TOKEN=ghp_xxx` is called with a non-`${VAR}` value.

Uses `Familiar.DataCase` for Repo setup. Flake stress test per the zero-tolerance policy (50 runs).

---

**Epic 8 Summary:** 5 stories. Ships the MCP client half: Familiar can consume any MCP server from the growing ecosystem as a drop-in tool provider, with management UX (`fam mcp add/list/get/remove/enable/disable`) that mirrors Claude Code's so muscle memory transfers. Storage is an `mcp_servers` SQLite table; `config.toml` `[[mcp.servers]]` is a second source for checked-in project servers. `--read-only` is a capability filter, not a safety veto (Epic 7.6 removed the safety layer entirely; the honest boundary is the container). The server direction — Familiar exposing its tools to editors over stdio — is deferred to Epic 11 post-MVP on the grounds that pointing editors at the existing `fam` CLI gives you the integration already.

Post-MVP (beyond Epic 11): HTTP/SSE transport for remote MCP servers, MCP resources consumption (read-only data sources from external servers), MCP prompts capability, sampling (MCP-initiated LLM calls), `fam mcp import-claude` bulk import.

---

## Epic 11: MCP Server Support (5 stories — post-MVP, drafted 2026-04-10)

**Post-MVP.** Expose Familiar's tools and knowledge entries to external MCP clients (Claude Code, Cursor, VS Code, Windsurf, Zed, any future MCP-aware editor) over stdio. When this ships, a developer can drop `"familiar": {"command": "fam", "args": ["mcp", "serve"]}` into their editor's MCP config and their editor's agent gets direct access to Familiar's tool set, knowledge store, and workflows without leaving the editor.

**Why deferred:** Epic 8 (MCP client) is much higher-leverage: users augmenting Familiar with the entire npm/PyPI MCP server ecosystem > Familiar augmenting one editor at a time. And users who want Claude Code to drive Familiar already have a path — point it at the documented `fam` CLI commands, which are fully JSON-output-capable via `--output json`. MCP server support is a nice-to-have for deep editor integration; it's not on the critical path to a shippable product.

**Why keep it drafted now:** Epic 8 ships `Familiar.MCP.Protocol` as a pure transport-agnostic codec. Writing Epic 11 now, even as a deferred draft, validates that the codec API will actually work for the server direction and prevents Epic 8 from accidentally coupling the codec to client-specific assumptions.

**Design principles:**
- **Reuse the codec.** `Familiar.MCP.Protocol` and `Familiar.MCP.Dispatcher` from Epic 8 Story 8-1 are transport-agnostic — Epic 11 adds a stdio *server* transport on top, not a new codec.
- **stdio only, no HTTP.** Editors spawn MCP servers as subprocesses over stdio. HTTP/SSE transport for LAN-exposed daemons is a separate concern and belongs in a later epic if at all.
- **Tools and resources, not prompts and sampling.** The post-MVP MVP (so to speak) ships `tools/list`, `tools/call`, `resources/list`, `resources/read`. Prompts (editor-side autocomplete templates) and sampling (MCP-initiated LLM calls back into the client) stay out of scope until someone can point at a concrete user need.
- **No safety layer.** Per Epic 7.6, Familiar has no runtime safety. When Familiar is an MCP server, the editor's agent can call `write_file` or `run_command` without any prompt or veto — the expectation is that users running this are running Familiar inside a container (per `docs/sandboxing.md` from Story 7.6-2). The `fam mcp serve --read-only` flag is a *capability filter* — write tools simply aren't registered with the dispatcher in read-only mode, so the editor doesn't see them at all. No runtime check, no veto, no confirmation prompt; if a tool is in the response to `tools/list`, it can be called.

### Story 11-1: MCP Server Stdio Transport

As a developer building MCP server support,
I want a `Familiar.MCP.StdioTransport` GenServer that reads line-delimited JSON-RPC from stdin and writes responses to stdout,
So that editors can spawn Familiar as a subprocess and talk to it over pipes.

**Scope:** GenServer that owns stdin/stdout. Reads line-delimited JSON (the de-facto MCP framing). Passes decoded requests to an injected dispatcher and writes the result back. Handles partial reads, malformed JSON (returns `-32700` to stderr log + ignores), EOF (graceful shutdown). Injectable `:input_device` and `:output_device` opts so tests can use `StringIO`. Crash-safe: a handler raise returns `-32603` instead of killing the transport. Reuses `Familiar.MCP.Protocol` from Epic 8 Story 8-1 for encoding/decoding.

### Story 11-2: MCP Server — Tools Capability

As an editor user,
I want Familiar to expose its tool registry via MCP's `tools/list` and `tools/call` methods,
So that my editor's agent can call Familiar's tools — read files, spawn sub-agents, run workflows — without leaving the editor.

**Scope:** `Familiar.MCP.Server.Tools` — implements the MCP `tools/list` and `tools/call` methods on top of `Familiar.Execution.ToolRegistry`. `tools/list` walks the registry, serializes each tool's name, description, and parameter schema into MCP format (reuse `Familiar.Execution.ToolSchemas.for_tools/1`). `tools/call` dispatches through `ToolRegistry.dispatch/3`. Error mapping: tool timeouts → structured MCP error; unknown tool → `-32601`; runtime errors → `-32603` with the tool's error message. Implements the MCP handshake (`initialize`, `initialized` notification) — capabilities advertise `tools` only for this story. Excludes the MCP-client-registered tools from Story 8-2 by default (they come from external MCP servers; re-exposing them would create a loop if an editor happens to use both Familiar and one of the same external servers). A `--include-mcp-tools` flag on `fam mcp serve` lets users override if they know what they're doing.

### Story 11-3: MCP Server — Resources Capability

As an editor user,
I want Familiar's knowledge store to be browseable and readable via MCP `resources/list` and `resources/read`,
So that my editor can surface Familiar's learned conventions and decisions as pinned context without re-embedding my codebase.

**Scope:** Extends `Familiar.MCP.Server` capabilities with `resources`. `resources/list` returns every `Familiar.Knowledge.Entry` as a resource with URI `familiar://knowledge/{id}`, `name` = first 60 chars of text, `mimeType` = `text/plain`, and metadata block (type, source, source_file, inserted_at). `resources/read` fetches an entry by URI and returns the full text. Pagination via MCP `cursor` pattern (100 entries per page default).

### Story 11-4: `fam mcp serve` CLI Subcommand

As a developer configuring my editor,
I want a `fam mcp serve` command that runs Familiar as an MCP stdio server,
So that I can drop `"familiar": {"command": "fam", "args": ["mcp", "serve"]}` into my editor's MCP config and be done.

**Scope:** Adds the `serve` subcommand to the `fam mcp` command group (the group itself already exists from Epic 8 Story 8-4). `fam mcp serve` boots the full application (Repo, ToolRegistry, extensions), then starts `Familiar.MCP.StdioTransport` with the server dispatcher. Blocks until stdin closes. Supports `--json-rpc-debug` to log every request/response pair to stderr (useful while editors debug their MCP config). Supports `--read-only` as a capability filter that only registers read-class tools with the dispatcher (same name-pattern allowlist as Story 8-3's per-server `read_only` field — `list_*`, `get_*`, `read_*`, `search_*`, `query_*`, `describe_*`, `show_*`, `fetch_*`). Supports `--include-mcp-tools` to also expose tools that came from external MCP servers (off by default — see Story 11-2 rationale). Updates `fam --help` with an MCP server section and configuration snippets for Claude Code, Cursor, VS Code, and Zed.

**Project-dir resolution.** Delegates to `Familiar.Daemon.Paths.resolve_project_dir/1` (delivered by Story 7.5-8). `fam mcp serve` passes its `--project-dir` value through; env var and walk-up fallbacks are handled by the shared resolver. If resolution fails, this story's one additional responsibility is reframing the `:project_dir_unresolvable` error to include the editor-config snippet alongside the shell syntax:

```json
"familiar": {
  "command": "fam",
  "args": ["mcp", "serve"],
  "env": {"FAMILIAR_PROJECT_DIR": "/absolute/path/to/project"}
}
```

Because walk-up lookup is part of the shared resolver, editors that spawn `fam mcp serve` with their own cwd inside a project tree will "just work" without any env-var plumbing — the resolver finds `.familiar/` by walking up from wherever the editor happened to be.

**Daemon coexistence.** If the Familiar daemon is already running for the same project, two Repo writers to the same SQLite file = lock contention. Decision deferred to implementation: either (a) `fam mcp serve` detects a live daemon via the existing daemon socket and proxies tool calls through it instead of opening its own Repo, or (b) it refuses to start with a clear `"daemon already running for this project — stop it first or use a different project dir"` error. Option (a) is strictly better UX; option (b) is a valid fallback if (a) proves too complex. This story must pick one and document the choice.

### Story 11-5: MCP Server Integration Test

As a developer,
I want an end-to-end test that runs the MCP server against a scripted fake MCP client,
So that a regression in transport, dispatcher, tools capability, or resources capability shows up before release.

**Scope:** Spins up `Familiar.MCP.StdioTransport` wired to paired `StringIO` devices. A test-side fake client sends JSON-RPC requests via the input device and reads responses from the output device. Test flow: (1) `initialize` handshake, (2) `tools/list` returns every built-in tool in `ToolRegistry`, (3) `tools/call` on `read_file` inside the project dir succeeds, (4) `tools/call` on a non-existent tool returns `-32601`, (5) `resources/list` returns a paginated knowledge entry list with correct cursor behavior, (6) `resources/read` on a known URI returns the full text, (7) malformed JSON on input returns `-32700` and the transport stays alive, (8) `--read-only` mode only lists read-pattern tools and returns `-32601` for write tools, (9) EOF on stdin gracefully shuts the transport down. Uses `Familiar.DataCase` for Repo setup. Flake stress test per the zero-tolerance policy (50 runs).

---

**Epic 11 Summary:** 5 stories. Post-MVP. Ships the MCP server half — Familiar exposed to editors over stdio. Reuses the codec/dispatcher from Epic 8 Story 8-1. No runtime safety (per Epic 7.6); `--read-only` is a capability filter; sandboxing is the container. Deferred indefinitely — promotable to active if and when editor integration becomes a priority and the `fam` CLI route isn't enough. Post-epic: HTTP/SSE transport, MCP prompts, MCP sampling.
