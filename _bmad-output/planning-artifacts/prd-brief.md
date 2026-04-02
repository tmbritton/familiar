# Familiar — PRD Executive Brief

*Distilled from the full PRD for contexts where the complete document (~800 lines) is too large. See `prd.md` for full details. Updated 2026-03-28 after UX design reconciliation.*

## What

Familiar is an AI agent platform that autonomously builds and maintains institutional memory about your codebase — decisions, rationale, gotchas, relationships. Agents use this knowledge to produce code that fits your project's conventions. Code is read fresh from the filesystem; the context store holds knowledge, not copies. The interaction model is hybrid: CLI for control, localhost Phoenix LiveView web UI for observation and review.

## Thesis

Model quality = f(context quality). A well-contextualized local 14B model produces code comparable to a frontier model with manually curated context. If this thesis fails, the project pivots or stops (kill criterion).

## Why

Developer sovereignty. Commercial tools enshittify. Familiar runs on your hardware, uses local models, stores knowledge locally, AGPL-3.0. No commercial interest to corrupt it.

## MVP Scope

Single-agent sequential pipelines. User describes intent → streaming reasoning trail shows the familiar's work → spec rendered in browser for review → task decomposition into four-level hierarchy (Epic → Group → Task → Subtask) → autonomous execution with self-validation and self-repair → knowledge captured post-task.

**3 tiers:** Core Loop (daemon, context store, work hierarchy tracker, planning engine, streaming trail) → Thesis Differentiators (init scan, hygiene loop, self-validation with duplicate detection, dual providers, autonomous self-repair) → UX (LiveView web UI, browser spec review, triage dashboard, notifications, rollback, recovery)

## Key Numbers

- ~87 Functional Requirements across 11 capability areas
- 26 measurable success metrics (Hard / Aspirational / Feel)
- 7 user journeys (setup, first run, daily work, unattended, failure, bug, debugging)
- ~20 CLI commands (organized by intent: daily vs. occasional)
- 3 default roles (analyst, coder, reviewer)
- 8 LiveView web UI components (spec renderer, triage, search picker, activity feed, knowledge browser, help overlay, status bar, work hierarchy)
- Target: Apple M1/M2 Pro, 16-32GB, local 14B model

## Top 10 FRs

1. FR1: Initialize project with automated scanning (atomic — completes or leaves no trace)
2. FR8: Create/maintain semantic knowledge store (facts, decisions, gotchas, relationships)
3. FR11: Autonomously refresh stale context on every task dispatch
4. FR20: Natural language feature planning with context-aware conversation
5. FR24: Generate spec with verified claims, flagged assumptions, stored as plain markdown
6. FR25: Spec review in browser with verification marks, knowledge links, approve/edit/reject
7. FR32: Four-level work hierarchy (Epic → Group → Task → Subtask) with drill-down triage
8. FR48: Self-validate output (tests, build, lint, requirement coverage, duplicate detection)
9. FR57: Unified recovery at any level — `fam fix` with pre-analyzed failure and proposed options
10. FR71: Localhost Phoenix LiveView web UI served from the daemon, zero-config

## Success Criteria (Key)

- **Kill criterion:** Local+context ≈ frontier+manual context on moderate/complex tasks
- **Ablation:** Context-on must exceed context-off by 30+ points
- **Unattended:** 8+ hours, no degradation, at scale (100+ files, 5K+ lines)
- **User satisfaction:** 80%+ sessions rated Impressed or Acceptable
- **Dispatch confidence:** User trusts specs enough to `fam do --all` and walk away
- **Baseline phase:** First 50 tasks calibrate all aspirational targets

## Innovation

1. **Context-aware planning that never repeats itself** — novel clarifying questions sharpen the user's intent; repeat questions are system failures eliminated as context grows
2. **Institutional memory for code generation** — no existing tool maintains persistent project knowledge across sessions
3. **Hybrid CLI + LiveView** — browser-rendered spec review with inline verification marks, knowledge links, and keyboard navigation. Terminal for control, browser for evaluation

## Domain Risks

Structural LLM mitigations: default-skip vendor files, prompt isolation, knowledge-not-code storage, spec verification with freshness, per-session frontier consent, duplicate code detection. No heuristic detection systems. Autonomous self-repair handles most failures without user involvement.

## Next Steps

Architecture → Epics/Stories → Implementation. All downstream work traces to this PRD and the UX Design Specification.
