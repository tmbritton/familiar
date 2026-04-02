---
validationTarget: 'docs/prd.md'
validationDate: '2026-03-27'
inputDocuments: [docs/prd.md]
validationStepsCompleted: [step-v-01-discovery, step-v-02-format-detection, step-v-02b-parity-check]
validationStatus: IN_PROGRESS
---

# PRD Validation Report

**PRD Being Validated:** docs/prd.md
**Validation Date:** 2026-03-27

## Input Documents

- PRD: prd.md ✓

## Pre-Validation: Pre-mortem Analysis

Pre-mortem elicitation identified six downstream failure scenarios traceable to PRD gaps:

| # | Failure Scenario | Root Cause | Severity |
|---|---|---|---|
| 1 | MVP scope ambiguous — developers can't reconcile full system description with exclusion list | No reconciled MVP section mapping components IN vs OUT | High |
| 2 | No way to validate "done" — no measurable success criteria | Missing **Success Criteria** section (BMAD required) | High |
| 3 | UX designer can't produce interaction flows — no end-to-end user walkthrough | Missing **User Journeys** section (BMAD required) | High |
| 4 | Architects reverse-engineer requirements from prose — inconsistent interpretations | Missing **Functional Requirements** section (BMAD required) | High |
| 5 | System built without latency, concurrency, or storage targets | Missing **Non-Functional Requirements** section (BMAD required) | High |
| 6 | PRD locks in implementation choices (Burrito, Ratatouille, sqlite-vec, RESP, Elixir structs) | Architecture/implementation details mixed into PRD instead of staying at capability level | Medium |

These findings will be validated and expanded during the formal validation steps that follow.

## Pre-Validation: User Persona Focus Group

Five target personas reacted to the PRD. Key gaps by theme:

| Theme | Personas Affected | Priority |
|---|---|---|
| No onboarding/first-use journey — users can't picture their first 10 minutes | Solo Dev, Content Strategist | High |
| Multi-user/team model absent — no concurrent access, shared daemon, or collaboration story | Team Engineer | High |
| Operational/observability requirements missing — no logging, metrics, health checks, degradation scenarios | DevOps Engineer | High |
| Domain-agnostic claim unsubstantiated — every example is software dev, zero non-dev journeys or role examples | Team Engineer, Content Strategist | Medium |
| Hardware/system requirements undefined — RAM, GPU, disk, minimum Ollama specs unknown | Solo Dev | Medium |
| Extensibility/contributor story absent — no plugin API, no protocol spec, no third-party developer guidance | OSS Contributor | Medium |
| Licensing implications unexplored — AGPL-3.0 impact on team/enterprise adoption not addressed | Team Engineer | Low |

## Pre-Validation: First Principles Analysis

Five core assumptions were stripped down and rebuilt from fundamental truths:

| # | Assumption as Stated | Verdict | What PRD Should Establish |
|---|---|---|---|
| 1 | Local models perform competitively for execution-level work | Conditionally true | Define "execution-level" bounds concretely; acknowledge frontier fallback path; state target model size class and hardware implications |
| 2 | Daemon-client TCP enables "work from anywhere" | Principle sound, implementation conflated | State the principle (compute/UI separation) at PRD level; leave TCP/WebSocket choice to architecture; address auth, TLS, NAT traversal as requirements |
| 3 | OTP supervision eliminates application-level error handling | Overstated | OTP handles process crashes, not task resumption, file atomicity, or LLM call idempotency — these require explicit design and should be captured as requirements |
| 4 | Domains are just different markdown files | Architecturally sound but incomplete | Explicitly connect MCP extensibility as the domain adaptation mechanism; without this, the domain-agnostic claim is hollow |
| 5 | Single binary with no runtime dependencies | Misleading | Binary is self-contained; system is not — Ollama, models, API keys, hardware are real prerequisites that must be listed |

**Rebuilt foundation:** The PRD's core ideas are sound but each needs tighter scoping, explicit bounds, and separation of principle from implementation choice.

## Pre-Validation: Stakeholder Round Table

Five stakeholders (Product Owner, Lead Architect, User Advocate, Business Strategist, Risk Officer) reviewed the PRD.

**Consensus on strengths:** BEAM/OTP is the right runtime, daemon-client separation is architecturally sound, domain-agnostic positioning is strategically smart, co-located daemon provides a strong data privacy story.

**Consensus on core issue:** The PRD reads as an architecture sketch, not a product requirements document. It describes *how* the system is built but not *what it promises users, how it keeps them safe, or what success looks like*.

**Negotiated priorities:**

| Requirement | Sponsor | Priority |
|---|---|---|
| Safety/permission model for agent actions (sandboxing, approval gates, no unsupervised destructive ops) | Risk Officer | Must-have |
| Human-in-the-loop control surfaces (pause, reject, redirect, approve — not just CANCEL) | User Advocate | Must-have |
| Onboarding/prerequisites as product requirements (reduce 5-step prerequisite chain) | Business Strategist | Must-have |
| Cost control / rate limiting for LLM API calls | Risk Officer | Should-have |
| Protocol versioning strategy | Lead Architect | Should-have |
| Context store data handling policy (secrets filtering, retention, PII) | Risk Officer | Should-have |
| Zero-config / frontier-only starter mode | Business Strategist | Nice-to-have |
| AGPL implications documented for enterprise adoption | Risk Officer | Nice-to-have |

## Pre-Validation: Red Team vs Blue Team

Adversarial attack-defend analysis across five vectors. Red Team won all five.

| # | Attack Vector | Victor | Severity |
|---|---|---|---|
| 1 | Local model bet is unsubstantiated — no benchmarks, no bounds, no fallback strategy | Red Team | High |
| 2 | Document is an architecture doc cosplaying as a PRD — zero FRs, NFRs, success criteria, or user journeys | Red Team | Critical |
| 3 | MVP scope incoherent — 70% of PRD describes post-MVP features without clear phasing or delineation | Red Team | High |
| 4 | No security/permission model — LLM-driven agents have unsupervised file write, git, and tool execution with no sandboxing, approval gates, or audit trail | Red Team | Critical |
| 5 | Domain-agnostic claim unfalsifiable — every example is software dev, no extensibility requirements defined | Red Team | Medium |

**Hardening recommendations:**
1. Restructure: extract architecture into separate doc, rebuild PRD around user-facing requirements
2. Add security/permissions as first-class functional requirements (sandboxing, approval gates, file boundaries, audit)
3. Bound local model claim with task categories, quality expectations, fallback behavior, hardware specs
4. Reconcile MVP with vision via explicit phasing (MVP → v2 → Vision)
5. Substantiate domain-agnosticism with extensibility requirements and a second-domain example, or reposition scope

## Format Detection

**PRD Structure (## Level 2 headers):**
1. Overview
2. Design Philosophy
3. Architecture
4. Agent Team
5. Context Store
6. Workflow System
7. Skills System
8. MCP Integration
9. CLI & TUI
10. LLM Provider Support (v1)
11. Filesystem & Remote Access
12. Project Directory Structure
13. MVP Scope
14. Future Directions
15. Open Questions

**BMAD Core Sections Present:**
- Executive Summary: Present (as "Overview")
- Success Criteria: Missing
- Product Scope: Missing (MVP Scope exists but is a checklist, not a proper scoped phasing section)
- User Journeys: Missing
- Functional Requirements: Missing
- Non-Functional Requirements: Missing

**Format Classification:** Non-Standard
**Core Sections Present:** 1/6

## Parity Analysis (Non-Standard PRD)

### Section-by-Section Gap Analysis

**Executive Summary:**
- Status: Incomplete
- Gap: Overview section provides vision and product description but lacks explicit problem statement, named target user segments, and clear differentiator statement
- Effort to Complete: Minimal — raw material exists in Overview and Design Philosophy, needs restructuring

**Success Criteria:**
- Status: Missing
- Gap: No measurable goals, KPIs, or definition of success. MVP checklist defines what to build but not what success looks like. Needs SMART criteria including context-injection thesis validation and target hardware benchmarks
- Effort to Complete: Significant — requires new content creation

**Product Scope:**
- Status: Incomplete
- Gap: MVP Scope provides checklist but no phasing (MVP → v2 → Vision). Architecture sections describe features without phase tagging. Future Directions reads as a wish list, not a scoped roadmap
- Effort to Complete: Moderate — content exists across multiple sections but needs restructuring into phased scope

**User Journeys:**
- Status: Missing
- Gap: No user personas, flows, or end-to-end journey descriptions. TUI wireframe implies interaction but doesn't walk through usage. Needs MVP journey (init → task → observe → iterate) and "aha moment" journey
- Effort to Complete: Significant — requires new content creation

**Functional Requirements:**
- Status: Missing
- Gap: Capabilities described implicitly in architecture prose but no discrete, testable FRs. Cannot write acceptance tests from this document. Needs extraction of FRs with acceptance criteria
- Effort to Complete: Moderate — capabilities exist in prose, need systematic extraction and formalization

**Non-Functional Requirements:**
- Status: Missing
- Gap: No performance targets, scalability limits, storage constraints, or security requirements. Needs measurable NFRs for inference latency, context store query time, storage growth, and critically the security/permission model
- Effort to Complete: Significant — requires new content creation including benchmarking targets and security model

### Overall Parity Assessment

**Overall Effort to Reach BMAD Standard:** Substantial
**Recommendation:** This document is better characterized as an architecture sketch or technical design document than a PRD. The recommended path is to extract the architecture content into a dedicated architecture document and rebuild the PRD from scratch using BMAD Create PRD workflow, referencing this document as input. This preserves all the valuable technical thinking while creating a proper requirements foundation.

## Validation Findings

[Findings will be appended as validation progresses]
