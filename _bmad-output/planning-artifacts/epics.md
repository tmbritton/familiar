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

**Deferred until Epic 5 is complete.**

CLI commands for managing roles (`fam roles`), skills (`fam skills`), workflows (`fam workflows`), and extensions (`fam extensions`). Interactive session timeout/resume for multi-turn workflow steps. Language extensibility via config files. Scope depends on what Epic 5 and 6 reveal about the management surface area.

---

**Phase 3 note:** Epics 6-8 are intentionally light. Detailed story breakdowns will be written when Epic 5 nears completion and the harness capabilities are proven. Vision clarifies as work commences.
