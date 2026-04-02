---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments: [docs/arch-sketch.md, docs/prd-validation-report.md, _bmad-output/planning-artifacts/ux-design-specification.md]
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 0
  projectDocs: 2
workflowType: 'prd'
classification:
  projectType: agent_platform
  csvType: developer_tool
  domain: ai_agent_tooling
  complexity: medium-high
  projectContext: greenfield
  annotations:
    - async-first interaction (dispatch-and-return primary)
    - self-validating agent output (FR)
    - output quality is kill criterion (success criteria)
  requirementLenses:
    - infrastructure lens → NFRs
    - knowledge system lens → Context Store FRs
---

# Product Requirements Document — Familiar

*Reconciled with UX Design Specification on 2026-03-28. Changes: renamed from Anthill, added hybrid CLI + LiveView web UI, four-level work hierarchy (Epic → Group → Task → Subtask), autonomous self-repair, streaming reasoning trail, and 17 new functional requirements (FR7b-FR7d, FR19b-FR19c, FR24b, FR56b, FR57b, FR71-FR79). Updated context freshness to autonomous refresh, planning efficiency to track repeat questions only.*

**Author:** Buddy
**Date:** 2026-03-27
**License:** AGPL-3.0

## Table of Contents

- [Executive Summary](#executive-summary)
- [What Makes This Special](#what-makes-this-special)
- [Project Classification](#project-classification)
- [Success Criteria](#success-criteria) — Hard/Aspirational/Feel framework, 26 metrics, kill criterion
- [Product Scope](#product-scope) — MVP tiers, growth gate, vision, risk mitigation
- [User Journeys](#user-journeys) — 7 journeys grounded in a Go/Datastar/SQLite karaoke app
- [Functional Requirements](#functional-requirements) — ~87 FRs across 11 capability areas (the capability contract)
- [Non-Functional Requirements](#non-functional-requirements) — Performance, reliability, agent quality, integration, maintainability
- [Domain-Specific Requirements](#domain-specific-requirements-llm-risk-mitigations) — LLM risk mitigations
- [Innovation & Novel Patterns](#innovation--novel-patterns)
- [Developer Tool / Agent Platform Specifications](#developer-tool--agent-platform-specifications) — CLI, workflows, roles, config

## Executive Summary

AI coding tools produce generic output because they start every session without project context. Users either manually curate context for each task or accept code that ignores existing patterns, conventions, and architectural decisions. The cost compounds — generated code that doesn't fit requires as much rework as writing it from scratch.

Familiar solves this by autonomously building and maintaining institutional memory about your project — the knowledge a senior developer carries in their head but never writes down. Why decisions were made, which architectural patterns to follow, what gotchas to avoid, how components relate. The context store holds *knowledge about the code*, not a copy of it. Actual code is read fresh from the filesystem at execution time. As agents complete tasks, new knowledge is captured — decisions, discoveries, relationships. A post-task hygiene loop prunes stale entries. Over time, every task benefits from everything that came before — the system gets smarter, not just bigger.

The interaction model is hybrid: a CLI for control (planning, execution, fixing) and a localhost Phoenix LiveView web UI for observation and review (spec review, triage dashboards, knowledge browsing). The CLI is where the user commands; the browser is where they evaluate. The daemon serves both from the same BEAM process — real-time updates are native, not polled.

The core thesis: model quality is a function of context quality, not just parameter count. A well-contextualized local model produces code that respects your naming conventions, reuses your existing modules, and follows your established patterns — code that looks like you wrote it. If local models fall short for a given task, swap to a frontier provider and the context advantage still holds.

Familiar is built on a conviction that developers should own their tools. It runs on your hardware, uses local models by default, stores knowledge locally, and is licensed AGPL-3.0. There is no commercial entity to raise prices, gate features, or degrade the experience. The system can't be enshittified because there's no commercial interest to corrupt it.

Familiar's long-term vision is a general-purpose autonomous workflow executor for knowledge work — the architecture is domain-agnostic, and the same system that learns coding conventions could learn brand voice, research methodology, or campaign strategy. This PRD defines the MVP that validates the core thesis: a single-agent, context-powered coding tool for solo developers.

The system is designed for contributions across disciplines — Elixir developers, AI/ML researchers, UX designers, domain experts, and technical writers all have a place in shaping Familiar's future.

## What Makes This Special

- **Self-maintaining institutional memory.** The context store holds knowledge about the code — decisions, rationale, gotchas, relationships — not a copy of the code itself. Code is read fresh from the filesystem. The system discovers, accumulates, and curates this knowledge autonomously. Users give tasks, not context.
- **User override, not black box.** Users can search, inspect, edit, and delete anything in the knowledge base. Autonomous doesn't mean opaque.
- **Trust as foundation.** Every operation is atomic with clean rollback. The user dispatches a task and walks away confident that either it succeeds completely or nothing bad happens. Self-validation (test execution, compilation checks) is built in, not optional.
- **Model-agnostic.** Local models are the default and aspiration. The context advantage holds regardless of provider — the differentiator is the knowledge, not the model.
- **Solo-maintainable.** Designed to be built and maintained by a single developer. Boring technology, minimal dependencies, stable interfaces.
- **Set it and forget it.** The user describes intent, reviews the spec, dispatches execution, and walks away. The system self-repairs failures, refreshes stale context, and retries — involving the user only for genuine ambiguities that require human judgment. Working software waits when you come back, with anything that needs you clearly flagged.
- **Hybrid CLI + web UI.** CLI for control (commands, conversations, execution dispatch). Localhost Phoenix LiveView web UI for observation and review (rendered specs, triage dashboards, knowledge browsing, search). Both surfaces serve the same data from the same BEAM process.

## Project Classification

- **Project Type:** Agent platform (developer tool for MVP)
- **Domain:** AI agent tooling — domain-specific concerns include model reliability, code safety, cost control, context integrity, and data provenance
- **Complexity:** Medium-High — technically ambitious (OTP process orchestration, semantic search, LLM non-determinism, novel AI safety surface) with no established playbook for this combination
- **Project Context:** Greenfield

## Success Criteria

*Targets are classified as Hard (non-negotiable, enforced in code or automation), Aspirational (initial estimates, calibrated after baseline measurement of first 50 tasks), or Feel (personal judgment, the ultimate measure of whether the tool is worth using). Metrics that prove redundant or unmeasurable during baseline phase will be dropped.*

### User Success

- Dispatch a multi-task feature build, leave it running unattended (overnight/weekend), and return to code that passes tests, meets functional requirements, and matches established codebase conventions. *(Feel)*
- The system handles task execution without requiring human intervention — clarification requests are the exception, not the norm. *(Aspirational)*
- After initial project scan, the user never manually provides context. The system knows what it needs to know. *(Hard)*
- User can locate any specific context entry within 3 search queries. *(Aspirational)*
- Task failure is reported within 30 seconds of detection, with clear explanation of what went wrong and what was rolled back. *(Hard)*
- First successful task completes within 30 minutes of initial project setup (init scan + first task dispatch). *(Aspirational)*
- After every 10-task session, user rates overall satisfaction: Impressed / Acceptable / Disappointed. Target: "Impressed" or "Acceptable" for 80%+ of sessions. *(Feel — the metric that actually determines whether the project continues)*

### Technical Success

- **Context retrieval relevance:** 80%+ of injected context entries are directly relevant to the current task, as measured by blind relevance audit. *(Aspirational — calibrate after 50 tasks)*
- **Context freshness:** On task dispatch, top-N retrieved entries are validated against current file state. Entries referencing deleted files are excluded; entries referencing modified files are autonomously refreshed. *(Hard — enforced at runtime)*
- **Context improvement over time:** The fifth task in a session produces measurably better-fitting code than the first, demonstrating compounding knowledge. *(Feel)*
- **Context curation quality:** Context store grows at the minimum rate necessary to maintain retrieval relevance above threshold. Over-pruning that drops relevance is a failure. *(Aspirational — threshold calibrated from baseline)*
- **Init scan quality:** System classifies project files into index/skip/ask. 90%+ correctly classified without user correction. *(Aspirational — calibrate after running on 3+ real projects)*
- **Convention discovery accuracy:** Discovered conventions match actual project conventions for 90%+ of detected patterns. *(Aspirational — calibrate after running on 3+ real projects)*
- **Agent reliability:** Tasks complete or fail cleanly — no corrupted files, no partial writes, no orphaned state. Atomic operations with rollback on failure. *(Hard — enforced at runtime)*
- **Self-validation:** Agent runs tests and checks compilation before reporting completion. Failed validation triggers retry or clean abort. Agent-written tests must exercise actual behavior, assert on values/side effects, cover success + error paths. Self-validation includes requirement coverage check against task description. *(Hard — enforced in agent pipeline)*
- **Unattended stability:** System runs for 8+ hours without crashes, memory leaks, or degradation. Memory ≤2x baseline, retrieval ≤1.5x initial, no monotonic resource growth. Minimum project scale: 100+ files, 5K+ lines, 200+ context entries. *(Hard — automated stability test)*
- **Performance on target hardware:** Context retrieval <2 seconds, local model first tokens <5 seconds on Apple M1/M2 Pro 16-32GB. *(Hard — automated performance test)*
- **Task time bounds:** Individual tasks complete within 3x estimated human effort. *(Aspirational — multiplier calibrated from baseline)*
- **Code correctness beyond tests:** Manual review assesses logical correctness, appropriate abstractions, edge case handling. 80%+ of reviewed tasks have no logical errors beyond what tests catch. *(Feel)*

### Safety Criteria (Hard — enforced at runtime, non-negotiable)

- Agent never writes outside the project directory.
- Agent never commits to git without explicit user approval.
- Agent never deletes files it didn't create in the current task.
- Context store never persists secrets, API keys, or credentials detected in code.

### Thesis Validation

- A local 14B model with Familiar's autonomous context achieves comparable task-level acceptance rates to a frontier model with realistic developer-provided context (the level a competent developer typically provides in Claude Code). *(Aspirational — "comparable" defined after baseline)*
- **Ablation test:** Context-on acceptance rate must meaningfully exceed context-off, proving context is the differentiator. *(Aspirational — delta target calibrated from first ablation run; initial estimate: 30+ points)*
- Comparison must include moderate and complex tasks, not just trivial ones. *(Hard — test design requirement)*
- Validation requires both local (Ollama) and frontier (Anthropic) providers. *(Hard — both must be in MVP)*
- If the thesis is not validated after calibration, the project pivots or stops. This is the kill criterion. *(Hard)*

### Baseline Measurement Phase

The first 50 tasks constitute the baseline phase. During this period:
- All metrics are recorded but no aspirational targets are enforced
- Baseline data calibrates final targets for all aspirational metrics
- Metrics that prove redundant or unmeasurable are dropped
- Feel metrics are evaluated honestly — if the tool doesn't feel useful after 50 tasks, reassess before continuing

### Measurable Outcomes

| Metric | Type | Initial Target | Measurement |
|---|---|---|---|
| Task completion rate (moderate/complex) | Aspirational | 70%+ | Pass/fail per task, 3x timeout |
| Task acceptance rate | Aspirational | 90%+ | Binary accept/reject per task |
| Test regression rate | Hard | 0% | Automated suite before/after |
| New test quality | Hard | Exercises behavior, asserts values, covers errors | Agent pipeline enforcement + review |
| Requirement coverage | Hard | Agent confirms all task elements addressed | Self-validation coverage check |
| Convention adherence | Aspirational | Linter pass + pattern matching | Convention checks + formatter |
| Convention discovery | Aspirational | 90%+ correct | User review after init scan |
| Init scan classification | Aspirational | 90%+ correct | User review of file categories |
| Context relevance | Aspirational | 80%+ | Blind audit |
| Context freshness | Hard | Stale entries auto-refreshed on dispatch | File stat validation + auto-refresh |
| Context curation | Aspirational | Minimum growth maintaining relevance | Relevance-coupled tracking |
| Context ablation delta | Aspirational | 30+ points | With/without injection comparison |
| Context searchability | Aspirational | Found in 3 queries | Usability test |
| Code correctness | Feel | 80%+ no logical errors | Manual code review |
| User satisfaction | Feel | 80%+ Impressed/Acceptable | Self-rating per 10-task session |
| Failure notification | Hard | <30 seconds | Automated timing |
| Time to first value | Aspirational | <30 minutes | End-to-end timing |
| Unattended runtime | Hard | 8+ hours, no degradation | Automated stability test at scale |
| Performance | Hard | Retrieval <2s, inference <5s | Automated on target hardware |
| Spec accuracy | Aspirational | 70%+ approved without edits | Specs approved vs edited |
| Planning efficiency | Aspirational | Repeat questions decrease as context grows; novel clarifications remain welcome | Repeat question count per feature over time |
| Assumption grounding | Aspirational | 90%+ verified against context | Verified vs unverified in specs |
| Decomposition accuracy | Hard | 0 dependency errors during execution | Blocked tasks that should be ready |
| Cross-plan conflict detection | Aspirational | Conflicts detected before execution | Caught vs discovered during execution |
| Plan freshness | Hard | Warn if plan >24h stale and files changed | Timestamp + file stat check |
| Provider failure recovery | Hard | Clean pause, no data loss, resumable | Kill provider mid-run, verify recovery |

## Product Scope

### MVP Strategy

**Approach:** Thesis-validation MVP. The smallest product that proves or disproves the core hypothesis: autonomous institutional memory makes local models produce code that fits. Features that don't contribute to thesis validation are deferred.

**Resource:** Solo developer — both a constraint and a design principle. Technology choices (Elixir/OTP, SQLite, markdown config) selected for this constraint.

**Target hardware:** Apple M1/M2 Pro, 16-32GB unified memory. Local model: 14B parameter class.

### MVP Feature Tiers

**Tier 1 — Core Loop** (must work for any task to succeed):
- Elixir daemon with single-agent task execution
- Context store with SQLite + sqlite-vec for semantic search
- Local embedding model via Ollama
- Discovery prompt injection — top-N relevant knowledge entries injected before every task
- Context freshness validation on dispatch — stat check referenced files, auto-refresh stale entries (not just flag — refresh autonomously)
- Direct file operations
- Role loading from markdown files
- Work hierarchy tracker: Epic → Group → Task → Subtask. This is a framework with flexible depth — trivial features use Epic → Tasks (two levels), complex features use all four. Epics and groups decomposed at planning time, subtasks discovered at execution time. Persistence, state machine (ready → in-progress → validating → complete/failed/blocked), and dependency resolution
- Context-aware planning conversation engine — queries context store during planning, asks novel clarifying questions that sharpen the user's intent, never repeats a question the system should already know the answer to
- Spec generation with context-verified assumptions (unverified assumptions explicitly flagged), rendered as markdown files
- Task decomposition from spec into groups and tasks with dependency mapping
- Streaming reasoning trail — terminal output showing the familiar's reasoning during planning (what it's checking, what it verified, what it flagged). Each line corresponds to actual tool use, not post-hoc narrative

**Tier 2 — Thesis Differentiators** (must work to prove the thesis):
- Autonomous project initialization scan with file classification (index/skip/ask). Init is atomic — completes fully or leaves no trace
- Convention discovery and reporting with evidence (counts alongside conclusions)
- Post-task context hygiene loop (store knowledge, prune stale entries, detect invalidated context)
- Self-validating agent output (run tests, check compilation, verify requirement coverage, check for duplicate code against existing codebase, retry or abort)
- Dual LLM provider support: Ollama for local inference, Anthropic as frontier fallback (per-task `--provider` override)
- Task-to-file modification tracking
- Plan freshness validation before execution
- Provider failure handling (retry with backoff, pause execution after configurable threshold, resume when available)
- Autonomous self-repair: stale context auto-refreshed, failed subtasks auto-retried, duplicate code auto-detected. User involved only for genuine ambiguities requiring human judgment

**Tier 3 — User Experience** (must work to be usable, mixed thesis relevance — some features improve evaluation rigor, others are operational necessities. Growth gate depends on Tier 1+2, not Tier 3):
- Atomic file operations with rollback on failure. Unattended file conflicts save familiar's version as `.fam-pending` rather than blocking
- User-facing context search, inspect, edit, and delete
- Localhost Phoenix LiveView web UI served from the daemon — zero-config, auto-opens browser for spec review
- Spec review in the browser: rendered markdown with inline verification marks (✓ verified / ⚠ unverified), convention annotations, knowledge links, approve/edit/reject keybindings
- Triage dashboard in browser and CLI: worst-first sort (❌ → 🔧 → ⊘ → ✅), drill-down through work hierarchy
- `fam fix` unified recovery at any hierarchy level — opens with failure analyzed, ambiguity identified, concrete options proposed
- `fam cancel` with in-progress rollback
- Work hierarchy lifecycle (planning → active → complete → archived) at epic, group, and task levels
- Batch execution with cascading failure handling (skip dependent chain, continue independents)
- Cross-plan conflict detection when adding tasks to existing tracker
- Context maintenance: autonomous hygiene loop handles routine maintenance. `fam context --refresh` and `fam context --compact` for rare manual use. Health stats in `fam status`
- Knowledge store auto-backup after each successful batch. Manual backup and restore available
- OS-native system notifications (auto-detect terminal-notifier/notify-send) for execution completion and pause events
- Any `fam` command triggers init if `.familiar/` doesn't exist

### Growth Phase Gate

Growth phase begins only after:
- Thesis validation passes (local ≈ frontier acceptance rates on moderate/complex tasks)
- Ablation test confirms meaningful context contribution
- Unattended stability holds for 8+ hours at minimum project scale
- Task acceptance rate exceeds aspirational target (calibrated from baseline)

### Growth Features (Post-MVP)

- Multi-agent orchestration (User Manager, Project Manager, Implementer, Reviewer)
- Workflow definition files and DAG executor with branching/loops
- Enhanced web UI views (knowledge graph visualization, advanced triage dashboards, wide-screen layouts)
- MCP client pool for extensible tool access
- Protocol layer (TCP/RESP or WebSocket) for client-daemon separation
- Multiple concurrent agent processes
- Global context store layer (cross-project knowledge)

### Vision (Future)

The full arch-sketch ambition, contingent on earlier phases proving out.

- General-purpose autonomous workflow executor for knowledge work
- Domain-agnostic configurations (content, marketing, research, communications)
- Mobile client for task dispatch and progress monitoring
- Editor plugin (VS Code, Neovim)
- Remote daemon support (VPS/home server deployment)
- Skills system with semantic discovery
- Burrito packaging as single binary per platform
- Hot code reloading for role updates mid-task

### Explicitly Out of MVP

- Multi-agent parallelism (sequential pipeline only)
- MCP abstraction layer (direct file operations)
- Global config hierarchy (`~/.familiar/`)
- Remote daemon support
- Mobile/editor clients
- Skills system with semantic discovery
- Burrito single-binary packaging
- Domain-agnostic configurations beyond developer tooling

### Risk Mitigation

**Technical Risks:**

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Context retrieval quality insufficient for thesis | Medium | Critical | Baseline measurement (50 tasks); ablation test; iterate embedding model and chunking before declaring thesis failed |
| Local 14B model can't produce acceptable code with context | Medium | Critical | Model-agnostic design; swap to frontier; if no model works with context, thesis fails |
| OTP supervision doesn't prevent data loss on crash | Low | High | Atomic file operations; SQLite crash-safety; inter-step state persisted; explicit crash recovery testing |
| SQLite + sqlite-vec performance degrades at scale | Low | Medium | Stability test at minimum project scale; `fam compact`; vector search benchmarked on target hardware |
| Workflow executor too simple for real-world usage | Medium | Medium | Linear pipelines cover all MVP journeys; step-specific instructions add flexibility; migrate to richer format post-MVP |
| Web UI adds scope to a solo developer MVP | Medium | Medium | LiveView is a thin layer on existing data (same BEAM process, no JS build). Components are simple (rendered markdown, text lists, keyboard handlers). But it's still additional work — plan for it in the development timeline. Spec renderer and triage are highest priority; activity feed and knowledge browser can follow |

**Resource Risks:**

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Solo developer burnout / loss of interest | Medium | Critical | Thesis validation is first milestone — prove it works or stop. Boring technology reduces maintenance. |
| Scope creep during development | High | High | PRD defines explicit MVP boundaries. Kill criterion provides natural stopping point. |
| System prompts hard to get right | High | Medium | Three roles, not seven. Iterate during baseline phase. Markdown files — fast to edit and test. |

**Unconsidered risks:**
- Ollama API changes — keep provider interface thin and abstract
- Embedding quality varies by language/domain — test on real Go + Elixir projects during baseline
- Planning conversation asks repetitive questions despite growing context — measure repeat question rate; novel clarifying questions are valuable, but repeating previously answered questions is a system failure

## User Journeys

### Journey Summary

| Journey | Scenario | Key Validation |
|---|---|---|
| 0: Setup | Install Familiar and prerequisites | Onboarding, time to first value |
| 1: First Run | Init, plan, execute (canonical full flow, adaptive planning depth) | Init scan, convention discovery, planning flow, ambiguous intent handling |
| 2: Daily Work | Iterative features, multi-feature tracker, mid-task cancel | Task acceptance, conventions, context improvement, feature grouping, model comparison |
| 3: Unattended | Large feature overnight | Stability, completion rate, satisfaction |
| 3b: Chain Failure | Dependency failure → replan → resume → return to main loop | Cascading handling, `fam fix`, recovery |
| 3c: Compounding Bug | Bad test → trace → fix → flag downstream → return to main loop | File tracking, downstream flagging, test quality |
| 4: Debugging | Bad output → investigate → fix context → redispatch → return to main loop | Context search, logs, freshness, user overrides |

**Cross-cutting: Context Maintenance**
Freshness gate runs on every task dispatch. External codebase changes are detected automatically — missing files excluded, modified files auto-refreshed. `fam context --refresh` performs full reconciliation. `fam context --compact` consolidates redundant entries. `fam status` shows context health (entry count, retrieval time, staleness ratio, last refresh, backup status). User-created entries are always preserved during refresh.

**Design Principle: Planning Information Priority**
The planning conversation has three information sources in priority order: (1) context store — check first, don't ask what you can look up; (2) pattern inference — if every handler follows the same pattern, assume the next will too; (3) user — only ask about genuine ambiguities.

### Journey 0: Setup — "Getting Started"

Buddy checks the README. Prerequisites: Ollama running with embedding model (`nomic-embed-text`) and coding model (`qwen2.5-coder:14b`). Optional: Anthropic API key.

```
$ fam
No Familiar project found. Initialize? (y/n) y
Ollama detected at localhost:11434 ✓
Embedding model: nomic-embed-text ✓
Coding model: qwen2.5-coder:14b ✓
Frontier fallback: not configured (add with fam config)

Running init scan...
```

Under 5 minutes from first command to ready.

**Capabilities revealed:** Prerequisite detection, first-run setup, provider auto-detection, optional frontier config.

### Journey 1: First Run — "Does This Thing Actually Work?"

*Canonical complete flow. All other journeys abbreviate as "plans and approves as usual." The system asks novel clarifying questions that sharpen the user's intent — clear intents get fewer questions, vague intents get more. The system never repeats a question it should already know the answer to.*

Init scan completes:

```
Scanned 83 files
Indexed: 64 (Go source, templates, SQL migrations)
Skipped: 19 (go.sum, .git, vendor)

Discovered conventions:
  - Package structure: handler/, model/, db/, tmpl/, static/
  - Naming: snake_case files, CamelCase exports
  - DB pattern: repository pattern via db/ package
  - Template engine: Datastar templates in tmpl/
  - Error handling: wrapped errors with fmt.Errorf

Review conventions? (y/n)
```

Buddy corrects one classification. Five seconds.

**Clear intent example:**

`fam plan "Add a recently played section to the homepage showing the last 10 songs the user queued"`

Agent asks 2 clarifying questions (intent is clear, minimal clarification needed). Buddy answers.

Terminal streams the reasoning trail as the familiar works — checking context, reading files, verifying assumptions. Then the browser opens to a rendered spec with verified assumptions highlighted green, unverified flagged amber, conventions shown inline:

```
Feature: Recently Played
  Show last 10 completed plays for current user on homepage.
  Assumptions (verified in context):
  - Queue table has user_id and completed_at columns ✓ (db/migrations/002_queue.sql)
  - Homepage handler receives user from session ✓ (handler/home.go)

  Conventions applied:
  - handler/recently_played.go (consistent with handler/song.go)
  - db/recently_played_repo.go (consistent with db/song_repo.go)
```

Buddy approves in the browser (`a` keybinding). 4 tasks generated with dependencies, organized into a group. Task list reviewed and approved.

`fam do --all` — twenty minutes. Code follows conventions. It looks like he wrote it.

**Vague intent example (later that day):**

`fam plan "Make the search better"`

Agent gauges low clarity, asks more questions. Buddy clarifies: fuzzy matching with FTS5, search-as-you-type with Datastar. Says "enough, generate the spec" after 3 questions.

Spec includes context-verified assumption: "Datastar reactivity with debounced input (verified: existing Datastar patterns found in 4 templates)." 5 tasks. Vague intent transformed to precise work.

Total time from init to first completed feature: ~25 minutes.

**Capabilities revealed:** Complete planning flow, adaptive depth, context-verified assumptions, task review, streaming output, self-validation, context accumulation.

### Journey 2: Daily Work — "The Tuesday Morning Loop"

Two weeks in. 2 remaining low-priority tasks from lyrics feature. New idea: lyrics display with synchronized highlighting.

Plans and approves as usual. 8 tasks generated. Tracker shows features grouped with no conflicts detected between feature tracks. Buddy reorders priorities.

`fam do --batch 5` — highlighting tasks execute over an hour. By task #10 the agent references Datastar patterns from two weeks ago. Cross-session context working.

Mid-task #11, Buddy watches streaming output — agent adding debounce logic in wrong place. `fam cancel` — changes rolled back. Re-plans with more specific instructions. Executes correctly.

Later, compares local vs frontier: `fam do #8 --provider anthropic`. Local version functionally equivalent. Keeps local. Comparison logged.

Feature completes. Auto-archive prompt. Tracker shows only active features.

**Capabilities revealed:** Multi-feature grouping, conflict detection, reordering, `fam do --batch N`, streaming, `fam cancel`, re-plan, `--provider` override, feature auto-archive.

### Journey 3: Unattended — "The Weekend Build"

User accounts: registration, login, sessions, profiles, favorites.

Plans and approves (5 clarifying questions — large feature, more depth). Tweaks spec (bcrypt not argon2). 15 tasks. Reviews and approves.

Adds rate limiting via second `fam plan` — system checks existing tracker, no conflicts. Task #16 added, properly sequenced.

Friday evening: `fam do --all`

Saturday morning: 16/16 completed. 13 first attempt, 2 one retry, 1 two retries. All tests pass: 47 existing + 41 new. One template tweak. Everything else ships.

**Capabilities revealed:** Large feature planning, spec editing, incremental `fam plan`, cross-plan conflict check, `fam do --all`, overnight stability, retry.

### Journey 3b: Chain Failure — "The Dependency Breaks"

Task #5 (session middleware) fails. The system autonomously refreshes context and retries — but the failure is a genuine ambiguity (two conflicting session patterns in the codebase), not a stale context issue. Self-repair can't resolve it.

Saturday morning triage: 13/16 completed (3 self-repaired), 1 needs input (❌ #5 — ambiguous session strategy), 2 blocked (⊘ waiting on #5). Independent tasks completed on their own.

`fam fix #5` — the familiar has already analyzed the failure and presents options: "Cookie-based sessions (consistent with web handlers) or token-based (consistent with API handlers)?" Buddy picks cookie-based. New task replaces #5. `fam do --all` — cascades through unblocked chain. Done.

Returns to daily work loop.

**Capabilities revealed:** Autonomous self-repair (3 tasks fixed without user), cascading failure (skip dependents, continue independents), `fam fix` with pre-analyzed failure and proposed options, chain resume.

### Journey 3c: Compounding Bug — "The Weak Test"

Favorites don't persist. `fam tasks --modified-files store/favorites_repo.go` — traces to tasks #4, #9, #10.

`fam fix #4` — the familiar already identified the likely issue (missing foreign key constraint) and proposes a fix. Buddy confirms. Fix task executes. System flags #9 and #10 for review — re-runs them with refreshed context. Clean.

Returns to daily work loop.

**Capabilities revealed:** File modification tracking, `fam fix` with pre-analyzed failure, downstream flagging, autonomous context refresh on re-run.

### Journey 4: Debugging — "Why Did It Do That?" (Rare Fallback)

*This journey is rare by design — the system auto-refreshes stale context on dispatch and checks for duplicate code during validation. Manual debugging happens only when autonomous repair wasn't enough.*

Nav indicator task created a new helper when one already existed. Self-validation's duplicate detection didn't catch it because the new helper had a different signature. The code works but doesn't fit.

Buddy notices during code review. `fam review #12` — shows context entries injected, including one flagged as "refreshed during execution" that pointed to the wrong file path. Deletes the bad entry, runs `fam context --refresh tmpl/`. `fam fix #12` — the familiar replans with corrected context and uses the existing helper. Correct output.

Returns to daily work loop.

**Capabilities revealed:** Context search, injection log, freshness gate, user deletion, targeted refresh, `fam fix`.

### Journey Requirements Traceability

| Journey | Validates Success Criteria |
|---|---|
| 0: Setup | Time to first value, prerequisite detection, init atomicity |
| 1: First Run | Init scan quality, convention discovery with evidence, spec accuracy, browser spec review, planning flow, streaming reasoning trail, assumption grounding |
| 2: Daily Work | Task acceptance, conventions, context improvement, cancel/rollback, model comparison, feature lifecycle, cross-plan conflicts, work hierarchy drill-down |
| 3: Unattended | Stability (8h+), completion rate, satisfaction, decomposition accuracy, autonomous self-repair, auto-backup |
| 3b: Chain Failure | Autonomous self-repair, cascading handling, `fam fix` with pre-analyzed failure, triage (❌/🔧/⊘/✅), chain resume |
| 3c: Compounding Bug | Test quality, code correctness, file tracking, downstream flagging, duplicate detection |
| 4: Debugging (rare) | Context relevance, searchability, autonomous context refresh, `fam review` with context inspection, manual fallback |
| Cross-cutting | Autonomous context refresh on every dispatch, repeat question elimination, OS notifications, web UI triage |

## Functional Requirements

*An agent step is a complete unit of work that may involve multiple LLM calls and tool uses. The agent within a step has access to its configured tools and can use them iteratively until the step's objective is met.*

*Epic mapping: The 11 capability areas below are designed to map 1:1 to implementation epics. Each area is a coherent, independently deliverable set of capabilities.*

### Project Initialization & Configuration

- FR1: User can initialize Familiar on an existing project directory, triggering automated project scanning
- FR2: System can auto-detect installed LLM providers, available models, and project language
- FR3: System can scan project files and classify them as index, skip, or ask based on configurable skip patterns
- FR4: System can discover and report project conventions (naming patterns, package structure, error handling, template patterns) from indexed files
- FR5: User can review and correct convention discovery results and file classifications
- FR6: System can validate configured language commands (test, build, lint) during initialization
- FR7: User can configure LLM providers, models, language settings, and scan preferences via project-local config
- FR7b: Initialization is atomic — either completes fully or leaves no `.familiar/` directory. No partial state on failure
- FR7c: Any `fam` command in a directory without `.familiar/` triggers initialization automatically
- FR7d: Convention discovery reports evidence alongside conclusions (e.g., "snake_case files (61/64 files)")

### Context Store (Knowledge Management)

- FR8: System can create and maintain a semantic knowledge store containing navigational facts, decisions, gotchas, and relationships about the project
- FR9: System can embed knowledge entries using a local embedding model for semantic search
- FR10: System can retrieve relevant knowledge entries given a natural language query, ranked by semantic similarity
- FR11: System validates context freshness on every task dispatch — entries referencing deleted files are excluded, entries referencing modified files are autonomously refreshed (not just flagged)
- FR12: System can store new knowledge discovered during task execution (facts, decisions, gotchas, relationships) via a post-task hygiene loop
- FR13: User can search the knowledge store with natural language queries
- FR14: User can inspect, edit, and delete individual knowledge store entries
- FR15: User can trigger a full or partial project re-scan to reconcile the knowledge store — user-created and user-edited entries are preserved, only auto-generated entries are updated
- FR16: User can consolidate redundant knowledge entries
- FR17: User can snapshot the knowledge store and task tracker and restore — either fully or selectively to a specific point in time
- FR18: System can report knowledge store health (entry count, retrieval performance, staleness ratio, last refresh)
- FR19: System enforces knowledge-not-code rule — stores knowledge about code, never duplicates file contents
- FR19b: System auto-backs up the knowledge store and task tracker after each successful batch execution
- FR19c: System can auto-restore from backup on startup if database integrity check fails

### Planning & Specification

- FR20: User can describe a feature in natural language and initiate a planning conversation
- FR21: System can query the knowledge store during planning to avoid asking questions it can answer from context
- FR22: System can adapt planning conversation depth based on intent clarity
- FR23: User can end the planning conversation at any point and have the system generate a spec with stated assumptions
- FR24: System can generate a feature specification with claims verified against knowledge store and filesystem — verified claims marked, unverified assumptions flagged, and context sources cited. Specs are stored as plain markdown files in the project directory
- FR24b: System streams a reasoning trail to the terminal during planning — showing what it's checking, what it verified, and what it flagged. Each line corresponds to actual tool use. If agentic step-by-step planning is too slow or unreliable, the trail can be generated as a post-hoc summary of actual tool calls — the spec must stand alone regardless of whether the trail was live or buffered
- FR25: User can review and approve a generated spec in the browser (rendered LiveView with verification marks, knowledge links, approve/edit/reject keybindings) or via `--editor` flag in `$EDITOR`
- FR26: System can decompose an approved spec into an epic with groups and ordered tasks with dependency mapping. Groups represent functional slices of the epic. Groups are generated only when a feature naturally decomposes into 2+ distinct functional areas — a single-area feature produces Epic → Tasks directly, skipping the group level
- FR27: User can review and approve the generated task list, requesting regrouping if needed
- FR28: System can check for conflicts between new tasks and existing tasks in the tracker
- FR29: When cross-plan conflicts are detected, system recommends resolution options and user selects approach
- FR30: User can resume a suspended planning conversation
- FR31: System validates plan freshness before task execution — warns if referenced files changed since plan creation or if files created by completed tasks in the dependency chain no longer exist

### Task Management

- FR32: System persists a four-level work hierarchy (Epic → Group → Task → Subtask) with status (ready, in-progress, validating, complete, failed, blocked), priority, and dependencies. Epics and groups are planned upfront; subtasks are discovered during execution. Viewable with drill-down and worst-first sort (❌ → 🔧 → ⊘ → ✅). Status rolls up: any failed subtask = task ❌, self-repaired = 🔧, all green = ✅
- FR33: User can reorder task priority
- FR34: User can remove tasks with warning about dependent tasks
- FR35: User can view which tasks modified a specific file
- FR36: System can archive completed epics and prompt for archival when all tasks in an epic are complete
- FR37: User can discard an entire epic plan, removing its spec and all associated groups/tasks from the tracker

### Task Execution

- FR38: User can execute tasks — individually by ID, next by priority, next N in sequence, or all in dependency/priority order
- FR39: System can execute multi-step workflows where each step's output is available to subsequent steps
- FR40: System can run interactive workflow steps (multi-turn conversation with user) and autonomous steps (run to completion)
- FR41: System can read actual project files from the filesystem at execution time
- FR42: System can inject relevant knowledge (decisions, gotchas, relationships, navigation) into the agent prompt before execution
- FR43: Workflow steps can customize agent behavior beyond the default role definition
- FR44: User can cancel a running task with rollback of in-progress file changes
- FR45: User can execute a task with a specific LLM provider override
- FR46: System streams agent activity to the user in real time during task execution
- FR47: System generates an execution summary after batch completion showing: tasks completed, retries, failures, tests added, files modified

### Self-Validation & Reliability

- FR48: System validates task output by running configured test, build, and lint commands (evaluated by exit code), verifying that each element of the task description is addressed, and checking for unnecessary duplication of existing code
- FR49: System can retry a failed autonomous workflow step once before aborting
- FR50: System can rollback file changes atomically when a task fails or is cancelled
- FR51: System can restart a workflow from a failed step without replaying completed steps
- FR52: System can handle cascading dependency failures — skip dependent tasks, continue executing independent tasks, report the failure chain
- FR53: System can detect LLM provider failure, retry with backoff, and pause execution after a configurable retry threshold if provider remains unavailable. Paused tasks are marked as `⊘ provider unavailable` and resume automatically when the provider returns
- FR54: System can report task failure within 30 seconds of detection with explanation and rollback status
- FR55: System can track which files each task modified for downstream impact analysis
- FR56: System detects interrupted task state on daemon startup and recovers — rolling back partial file changes and marking the interrupted task as failed

- FR56b: In unattended execution, if a target file has been modified by the user since task start, system skips the conflicting write and saves the familiar's version as `.fam-pending`. User resolves on return

### Unified Recovery

- FR57: User can initiate unified recovery at any hierarchy level — `fam fix #N` for a task (numeric ID), `fam fix` without argument opens Telescope-style picker for selection. Fix conversation opens with failure already analyzed, ambiguity identified, and concrete resolution options proposed
- FR57b: System autonomously self-repairs where possible — refreshing stale context and retrying before involving the user. User sees only failures that require human judgment

### Safety & Security

- FR58: System enforces that agents can only read and write files within the project directory
- FR59: System enforces that agents cannot commit to git without explicit user approval
- FR60: System enforces that agents can only delete files created by the current task
- FR61: System enforces that agents can only execute shell commands defined in the language configuration
- FR62: System does not persist secrets, API keys, or credentials detected in code to the knowledge store
- FR63: System skips vendor and dependency directories by default during scanning, enforced on all ingestion paths
- FR64: System warns on first use of an external LLM provider per session and re-prompts after inactivity timeout

### Workflow & Role Configuration

- FR65: User can create, edit, and delete workflow definitions as markdown files
- FR66: User can create, edit, and delete role definitions as markdown files
- FR67: System validates workflow and role files on load, producing clear error messages for invalid files
- FR68: System can suspend interactive workflow steps after idle timeout and allow user to resume later
- FR69: User can add new language support by creating a configuration file without modifying system code

### Web UI (Localhost LiveView)

- FR71: Daemon serves a Phoenix LiveView web UI on a localhost port, auto-starting with the daemon. No separate setup required
- FR72: `fam plan` auto-opens the browser to the rendered spec review page on first spec generation per planning session. Subsequent specs in the same session update the existing tab via LiveView. Auto-open is configurable (`fam config`) and degrades gracefully if browser is unavailable (spec URL printed to terminal instead)
- FR73: Spec review page renders markdown with inline verification marks (✓ green / ⚠ amber), convention annotations, and navigable knowledge links
- FR74: User can approve, edit, or reject a spec via keyboard shortcuts in the browser (status bar shows available actions)
- FR75: Triage dashboard shows work hierarchy with worst-first sort, drill-down navigation, and live status updates via LiveView
- FR76: Search picker overlay (Telescope-style) is available from any view via `Space` keybinding — unified search across context entries, tasks, specs, and files with two-phase rendering (instant text matches, streaming semantic results)
- FR77: Web UI is fully keyboard-navigable with view shortcuts (`s`: spec, `t`: triage, `w`: watch, `l`: library, `?`: help, `Esc`: back)
- FR78: All CLI commands support `--json` output as a global flag — output format is an interface contract
- FR79: System sends OS-native notifications (auto-detect `terminal-notifier` on macOS, `notify-send` on Linux) for execution completion and pause events. Configurable in `fam config`

### Thesis Validation

- FR70: System supports thesis validation — executing tasks with different providers for comparison, with context injection disabled for ablation testing, and logging all injected context and execution details per task for analysis

**Known limitation:** Conflicting knowledge entries (contradictory patterns both valid in the codebase) are returned by retrieval without automatic resolution. Agent role prompts should include guidance for handling conflicting context.

## Non-Functional Requirements

### Performance

- Context store retrieval completes in under 2 seconds on target hardware (Apple M1/M2 Pro, 16-32GB) with 200+ entries
- Local model inference (14B) produces first output tokens within 5 seconds on target hardware
- Init scan completes within 5 minutes for projects up to 200 source files
- Daemon remains responsive to read-only commands (status, tasks, search, log) during task execution — read-only queries return within 1 second regardless of agent activity
- Web UI spec review page loads in under 1 second from `fam plan` completion to rendered spec in browser
- LiveView updates (triage status changes, search result streaming) delivered within 100ms of server-side event
- Web UI search: text matches appear in <50ms, semantic results stream in within 200ms
- Web UI supports at least 1 concurrent browser session (single user, localhost). Multiple tabs are permitted but not a design target

### Reliability

- File operations are atomic — either complete fully or roll back. No partial writes survive a crash or cancellation
- Context store and task tracker persist in crash-safe storage. No data loss on daemon crash or power failure. Database integrity checked on daemon startup — auto-restore from backup if corruption detected
- Daemon detects interrupted state on restart and recovers without user intervention
- Auto-backup of context store and task tracker after each successful batch execution
- System runs for 8+ hours executing sequential tasks without memory leaks or performance degradation (memory ≤2x initial baseline, retrieval time ≤1.5x initial)
- Minimum project scale for stability: 100+ source files, 5,000+ lines, 200+ context entries

### Agent Output Quality

- Agent output must pass the project's configured linter/formatter
- Agent must generate tests for new functionality — tests must exercise actual behavior, assert on return values or side effects, and cover at least one error/edge case path
- Agent follows conventions discovered during init scan and injected via the knowledge store
- System operates within model context window limits — when injected knowledge plus task content approaches model limits, the system prioritizes the most relevant context and warns about truncation

### Integration

- Ollama provider: system communicates via Ollama's HTTP API. Provider interface is thin and abstract — Ollama API changes should require minimal code changes
- Anthropic provider: system communicates via Anthropic's API. Same thin interface.
- Provider failure is handled gracefully — retry with backoff, pause, resume. No silent data loss or corrupted state on provider timeout

### Output Consistency

- Every CLI command supports `--json` with a consistent, documented schema. Interactive commands (`fam fix`, `fam plan` conversation mode) in `--json` mode emit events as newline-delimited JSON rather than interactive prompts
- `--quiet` mode outputs minimal text suitable for scripting on all commands
- Output schemas are documented in `fam --help` per command and treated as an interface contract — breaking changes are versioned

### Triage Tier Definitions

Precise definitions to prevent signal inflation:
- **✅ Complete:** Task succeeded with no retries after failure. Routine context refreshes on dispatch do not affect this status — context refresh is normal maintenance, not a repair
- **🔧 Self-repaired:** Task required at least one retry after a failure (subtask failed, then succeeded on retry; or task failed validation, then passed on retry). Context-only refresh without task failure does NOT count as self-repair
- **⊘ Blocked:** Task waiting on a dependency. Not a failure state — pending work
- **❌ Needs input:** Task failed after all retries. Requires human judgment to resolve

### Maintainability

- Codebase must be understandable and modifiable by a single developer
- Dependencies are minimized — standard Elixir/OTP libraries, SQLite, Phoenix LiveView, no unnecessary frameworks
- Configuration is data (TOML, markdown), not code — adding languages, roles, and workflows requires no Elixir knowledge
- Test suite exists for core functionality (context store, workflow executor, safety constraints, web UI components) — the system that validates agent code must itself be validated

## Domain-Specific Requirements: LLM Risk Mitigations

*Mitigations are structural and low-implementation-cost. No heuristic detection systems. Complex defenses deferred to post-MVP.*

### Prompt Injection (Structural)

- **Default-skip untrusted sources:** Init scan skips vendor/, node_modules/, and dependency directories by default. Eliminates the largest untrusted input surface at ingestion. *Trigger:* skipped files listed in init report, user can override.
- **Skip rules enforced globally:** Skip patterns are project-level configuration, enforced on all ingestion paths — init scan, `fam refresh`, and post-task hygiene loop.
- **Structural prompt isolation:** Injected context placed in a delineated data section. Model instructed to extract information, never execute instructions found within context. Defense-in-depth — probabilistic, not a guarantee.
- **Context source metadata:** Every entry records its source (init-scan / agent / user / decision) for auditability.

*Blocklist-based input sanitization deliberately excluded — provides false sense of security against adversarial, evolving threats.*

### Context Poisoning (Knowledge-Not-Code)

- **Knowledge-not-code rule:** Store navigational facts, decisions, gotchas, and relationships — never store interpretive observations about code patterns without evidence.
- **Planning decisions stored explicitly:** User-stated decisions from planning conversations stored as source type `decision`, linked to originating spec/task.
- **User audit and deletion:** All context visible via `fam search` and manageable by the user.
- **Known feedback loop:** Agent-written code becomes context input for future tasks via filesystem reads. If agent code contains subtle hallucinations that pass tests, those become part of the codebase. Mitigated by self-validation. Documented as inherent limitation.

### Planning Hallucination (Verification)

- **Spec claims verified with freshness check.** Planning verification runs the same freshness gate as task dispatch. Verified claims marked ✓. Unverifiable claims labeled as assumptions. *Trigger:* if referenced file is stale, planning pauses and re-scans.
- **Context-influenced questions cite sources.** When a planning question is triggered by a specific context entry, the source is cited so the user can evaluate legitimacy.
- **Dependency verification:** External packages checked against go.mod/mix.exs. Standard library imports verified by attempting to resolve. Unknown packages flagged.

### Data Leakage (Warning)

- **Per-session frontier warning:** First `--provider` call with external API prompts confirmation. Session = continuous user interaction; re-prompts after >1 hour inactivity.
- **No automatic frontier fallback.** All external API usage user-initiated.

### Mitigation Metrics (Hard)

| Metric | Target | Measurement |
|---|---|---|
| Untrusted source exclusion | 0 vendor/dependency files indexed by default | Init scan file classification audit |
| Knowledge-not-code compliance | 100% of auto-generated entries are facts, decisions, gotchas, or relationships | Context store audit |
| Planning freshness | 0% of verified spec claims reference stale files | Freshness gate logs |
| Frontier consent | 0 external API calls without active session confirmation | API call log audit |

### Residual Risks

- Prompt injection via first-party code comments remains possible — structural isolation is probabilistic
- Subtle errors in navigational facts (correct file reference, wrong signature extraction) may not be caught
- LLM non-determinism means mitigations work probabilistically
- Dependency verification confirms existence, not behavioral correctness
- Agent output → context feedback loop can propagate undetected hallucinations in code that passes tests
- Model supply chain integrity is an external dependency risk (Ollama's responsibility)

### Deferred to Post-MVP

- Tool call scope validation (fine-grained per-task allowlisting)
- Trust-level-based retrieval filtering
- Confidence scoring for context entries
- Contradiction detection between context entries
- API behavior verification for dependencies

## Innovation & Novel Patterns

**Context-Aware Planning That Learns.** Familiar's planning conversation queries the knowledge store before asking the user — checking what it already knows about conventions, patterns, and prior decisions. Planning asks fewer questions as knowledge accumulates. No existing tool demonstrates decreasing interaction cost as project knowledge grows. This provides immediate value from first use and improves over time.

**Institutional Memory for Code Generation.** The context store accumulates decisions, rationale, gotchas, and relationships — knowledge about the code, not the code itself. No existing AI coding tool (Claude Code, Cursor, Continue, Aider) maintains persistent institutional memory across sessions. This is both the core thesis and the long-term retention mechanism — accumulated knowledge doesn't transfer to other tools.

**Novelty is in the synthesis.** Individual pieces exist (RAG, local models, task planners). The combination — persistent knowledge that curates itself, context-aware planning, autonomous execution with self-validation, local-first — hasn't been built. If local models improve to the point where context injection is unnecessary, the planning and orchestration value remains. If cloud competitors add persistent memory, user-owned local sovereignty differentiates.

## Developer Tool / Agent Platform Specifications

### Supported Project Ecosystems

Familiar is language-agnostic. Code generation depends on the LLM model, not Familiar. Language-specific behavior (scanning, validation, dependency checks) is driven by pluggable configuration:

```toml
[language]
test_command = "go test ./..."
build_command = "go build ./..."
lint_command = "golangci-lint run"
dep_file = "go.mod"
skip_patterns = ["go.sum", "vendor/"]
source_extensions = [".go"]
```

New language support requires a config file, not code changes. MVP ships with configurations for Go and Elixir.

### Installation and Prerequisites

**Prerequisites:** Ollama installed and running with an embedding model and a coding model (14B+ recommended). Optional: Anthropic API key for frontier fallback.

**Installation (MVP):** Clone and build with `mix release`. Single binary output. Burrito packaging deferred to post-MVP.

**First run:** `fam` in a project directory triggers init if no `.familiar/` config exists. Auto-detects Ollama, models, and project language. Validates configured commands (test, build, lint) work before completing init.

### CLI Interface

Commands organized by user intent. All commands support `--json` (global flag, platform API) and `--quiet` (minimal output for scripting).

**Daily commands:**

| Command | Purpose |
|---|---|
| `fam plan "<desc>"` | Context-aware planning → streaming trail → spec in browser → task decomposition |
| `fam plan --resume` | Resume a suspended planning conversation |
| `fam do` | Execute highest-priority ready task |
| `fam do --all` | Execute all in dependency/priority order |
| `fam do --batch N` | Execute next N ready tasks |
| `fam do #N` | Execute specific task |
| `fam do #N --provider <name>` | Execute with specific LLM provider |
| `fam status` | Execution progress + triage + context health + backup status |
| `fam status --summary` | Headers only (no task detail) |
| `fam fix` | Open Telescope picker to select what to fix (task, group, or epic) |
| `fam fix #N` | Fix specific task — failure analyzed, options proposed |
| `fam search "<query>"` | Interactive TUI picker — semantic search across context, tasks, specs, files |
| `fam tasks` | View work hierarchy (grouped by epic/group, status, dependencies) |
| `fam cancel` | Cancel current task, rollback in-progress changes |

**Occasional commands:**

| Command | Purpose |
|---|---|
| `fam init` | First-run setup (also triggered automatically by any `fam` command) |
| `fam review #N` | Post-task detail: diff, context injected, self-repair status |
| `fam log #N` | Streaming trail replay for a task or feature |
| `fam log --system` | Verbose system logs for debugging (also `--json`) |
| `fam context --refresh [path]` | Re-scan project/path (routine maintenance is automatic) |
| `fam context --compact` | Consolidate redundant context entries |
| `fam context --health` | Context store health details |
| `fam backup` | Manual snapshot of knowledge store and task tracker |
| `fam restore` | Restore from snapshot (only command requiring confirmation) |
| `fam config` | Configure providers, models, notifications, preferences |

### Workflow System

Workflows are user-editable markdown files in `.familiar/workflows/` defining sequential agent pipelines. Each workflow has a unique trigger (an `fam` command). The executor runs agents one at a time, passing context between steps via the knowledge store.

Each workflow step declares its mode:
- **Interactive** — multi-turn conversation with user (planning, fixing)
- **Autonomous** — runs to completion without user input (implementation, validation)

Steps can include step-specific instructions that supplement the agent's role definition.

**Default MVP workflows:**

| Workflow | Trigger | Pipeline |
|---|---|---|
| feature-planning | `fam plan` | analyst [i] → coder [a] (spec + decompose) |
| feature-implementation | `fam do` | coder [a] (plan + implement) → reviewer [a] (validate + observe) |
| task-fix | `fam fix` | analyst [i] → coder [a] → reviewer [a] |

**Workflow requirements:**
- One trigger per workflow, no overrides or inheritance
- Invalid workflow files produce clear errors on load, not runtime crashes
- Interactive steps don't block indefinitely — suspended conversations are resumable
- Autonomous step failure: retry once, abort on second failure, rollback file changes
- Workflows can restart from a failed step, not from the beginning

### Role Definitions

Roles are user-editable markdown files in `.familiar/roles/` defining agent behavior, model selection, and available tools. The body of each file is the system prompt.

**Default MVP roles:**

| Role | Purpose |
|---|---|
| `analyst` | Planning and fix conversations (interactive) |
| `coder` | Spec writing, task decomposition, code implementation (autonomous) — prompt includes basic security awareness |
| `reviewer` | Validation (tests, compilation, requirements) and knowledge extraction (autonomous) — prompt includes QA thinking (edge cases, unhappy paths, test thoroughness) |

Three roles for MVP. The role/workflow system makes adding custom roles trivial (markdown file in `.familiar/roles/`, reference in a workflow). Post-MVP candidates: QA analyst, security reviewer, UX reviewer, documentation writer.

**Available agent tools (MVP):**

| Tool | Purpose | Safety Constraint |
|---|---|---|
| `read_file` | Read a project file | Project directory only |
| `write_file` | Write/create a file | Project directory only; atomic with rollback |
| `delete_file` | Delete a file | Only files created by current task |
| `run_command` | Execute shell command | Language config commands only (test, build, lint) |
| `search_context` | Query the knowledge store | Read-only |
| `store_context` | Write to the knowledge store | Knowledge-not-code rule enforced |
| `list_files` | List directory contents | Project directory only |

### Configuration

All configuration is project-local in `.familiar/`:

| Path | Purpose |
|---|---|
| `.familiar/config.toml` | Provider settings, language config, scan preferences |
| `.familiar/roles/*.md` | Agent role definitions |
| `.familiar/workflows/*.md` | Workflow definitions |
| `.familiar/familiar.db` | Knowledge store + task tracker (SQLite, preference not requirement) |

No global `~/.familiar/` configuration. Same roles needed across projects → copy the files.

### Documentation (MVP)

- README with setup, prerequisites, quickstart
- `fam--help` with per-command help and examples
- Example role, workflow, and language configuration files
