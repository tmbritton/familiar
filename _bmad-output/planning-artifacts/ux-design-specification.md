---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
lastStep: 14
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/prd-brief.md
  - _bmad-output/planning-artifacts/prd-validation-report.md
  - docs/prd-validation-report.md
---

# UX Design Specification — Familiar

**Author:** Buddy
**Date:** 2026-03-27

---

## Executive Summary

### Project Vision

Familiar is a CLI-first AI agent platform for solo developers that autonomously builds institutional memory about codebases. The UX philosophy is **git-style explicit commands** — the user is in control, issuing discrete commands for each phase of work (plan, execute, fix, observe). The system is not a chatbot; it's a tool that happens to understand natural language when needed.

The interaction model has two distinct modes:
- **Command mode** (primary): User issues `fam` commands, receives structured output, makes decisions
- **Conversation mode** (fallback): Used during planning and fix flows when the system has genuine knowledge gaps it can't resolve from context — but the system treats its own questions as defects to be eliminated, not interactions to be optimized

**Core UX Principles:**

1. **Zero context-switch.** Familiar fits into your existing workspace — half-screen terminal pane, narrow tmux split, integrated terminal. It never asks you to rearrange your environment. Commands are short to type, output fits without scrolling, interruptions are deferrable.
2. **Good neighbor.** Familiar runs alongside your active work, not in a vacuum. It never monopolizes stdout, never competes for attention, and handles the fact that you're changing the same codebase simultaneously. Pre-write file stat checks detect if target files changed since task start — the system pauses and asks rather than overwriting. Post-rollback restores the user's version of files, not the pre-task version. Task completions and failures surface as one-line unobtrusive notifications.
3. **Repetition is the only unforgivable question.** Novel clarifying questions that sharpen the user's vision are a feature — the familiar helping the wizard think. Repeating a question the system should already know the answer to is a system failure. The system stores every answer and never asks the same question twice. Success metric: repeat-questions trending to zero, while novel clarifications remain welcome. During cold-start, more questions are expected and framed as knowledge acquisition ("Learning your project"). As context grows, questions become rarer and more targeted.
4. **Trust through structure, delight through observation.** Confidence comes from guarantees — atomic rollback, self-repair, post-hoc review. Not from watching. The live view (`fam watch`) exists for ambient awareness and joy. The system must be fully trustworthy even if the user never watches execution.
5. **Intent-driven commands.** The CLI is organized around what the user wants to accomplish (build, fix, observe, manage), not around what the system can do. Commands are grouped by natural mental model, not forced into minimum count. Primary commands cover daily use; power commands are discoverable but never in the way.
6. **CLI output is the platform API.** `--json` is a global flag on every command. Output format is an interface contract, tested in CI. This enables dashboards, CI integration, notification hooks, and custom TUIs without building an API layer.
7. **Onboarding is a distinct mode.** First-run is not a simplified version of the power-user flow — it's a guided experience with explanations, orientation, and progressive hints that fade after ~5 sessions. The system explains what it's doing and why during init, orients the user on first plan, and gradually removes scaffolding as familiarity builds.

### Target Users

**Primary persona: Solo Developer ("Buddy")**
- Technically proficient, CLI-native, comfortable with terminal workflows
- Works on personal or small projects on Apple M1/M2 Pro (16-32GB)
- Values sovereignty: local models, local data, AGPL-3.0, no vendor lock-in
- Dispatch-and-forget mindset — wants to queue work and walk away (overnight, weekend builds)
- In practice, "walks away" means "does other work in the same terminal session" — editing code, reading docs, reviewing PRs. Familiar runs alongside, not in isolation
- Trusts the system to self-manage context; manual knowledge store interaction is rare
- Expects the system to self-repair on failure; only pulled in when self-recovery fails

**User spectrum (from persona focus group):**

Users range from time-constrained weekend builders to CLI power users to cautious adopters who've been burned before. Key tension: some want maximum automation ("just do it, I'll review"), others want maximum visibility ("show me every file you touch"). The UX must serve both through progressive disclosure and output format options — not by forcing a single interaction style.

### Key Design Challenges

1. **CLI information density at scale** — All list commands default to summary view with drill-down. Design and test output at 5, 20, and 50+ items. Active/actionable items always surface first; completed items collapse by default. Borrow visual grammar from tools developers already know: `git status` two-column layout, `cargo build` progress lines, `htop` persistent header bars. All output must be legible in a half-screen terminal pane — full-screen should never be required.
2. **Live execution as ambient awareness** — Tasks can run for extended periods. The live view (`fam watch`) is an opt-in structured activity display — ambient awareness, not a confidence mechanism. Shows what the agent is doing (reading, writing, testing, validating) as a live-updating status feed. Execution and observation are decoupled: `fam do` returns immediately, `fam watch` attaches, `q` detaches. Execution continues regardless. Must work in a narrow tmux split. **Design priority: core command output patterns (status, plan, do, review) must be fully designed before any live view work.**
3. **Planning as collaborative sharpening** — The system generates specs with context-verified assumptions and asks novel clarifying questions that sharpen the user's hazy vision into precise intent. Questions that surface edge cases or ambiguities are valuable — the familiar helping the wizard think. Repeat questions are system failures. Every answer is stored so it's never asked again. Success metric: repeat-questions trending to zero, while novel clarifications remain welcome.
4. **Error triage, not error lists** — After unattended runs, the system presents a triaged summary with three tiers: ✅ completed (first attempt) / 🔧 self-repaired (retried and passed, worth a glance) / ❌ needs input (failed after retry). Self-repaired tasks are distinguished because automated validation checks structural correctness but not intent alignment. `fam review #N` shows the full post-task picture.
5. **Trust calibration across three layers:**
   - **Confidence layer** (structural, always on): atomic rollback, self-repair, triage, post-hoc review, pre-write file stat checks
   - **Awareness layer** (ambient, opt-in): `fam watch` live activity feed, one-line completion notifications, project health map
   The confidence layer must work perfectly even if the user never uses `fam watch`.
6. **Output composability** — `--json` is a global flag on every command — the platform API for MVP. `--quiet` provides minimal output for scripting. Output format is an interface contract tested in CI. Enables dashboards, CI integration, notification hooks, and custom TUIs.
7. **Command surface organized by mental model** — Commands grouped by user intent, not forced into minimum count:

| Intent | Command | Covers |
|---|---|---|
| **Build** | `fam plan` → `fam do` | plan, approve spec, execute (single/batch/all), provider override |
| **Fix** | `fam fix` | view failure, replan, fix, flag downstream; `--feature` for spec-level recovery |
| **Observe** | `fam status` | progress, triage, context health |
| | `fam watch` | live activity feed (opt-in) |
| | `fam review #N` | post-task detail: diff, context injected, self-repair status |
| **Search** | `fam search` | query context store (top-level — it's a daily action) |
| **Manage** | `fam context` | refresh, compact, health (admin operations) |
| | `fam backup` / `fam restore` | top-level (infrequent but high-stakes, not buried in subcommands) |
| **Configure** | `fam config` | providers, models, language settings, notification provider |
| **Tasks** | `fam tasks` | detailed task management, reorder, remove, feature drill-down |
| **Setup** | `fam init` | first-run project initialization |

Daily commands: `plan`, `do`, `status`, `fix`, `search`, `tasks`. Everything else is occasional.

8. **Good neighbor with concurrent editing** — The system runs alongside active work and must handle the case where the user modifies files Familiar is reasoning about. Pre-write file stat check: if a target file changed since task start, pause and ask rather than overwrite. Post-rollback restores the user's file version, not the pre-task snapshot. `fam status` returns in <1 second.
9. **Onboarding as distinct experience** — First-run (`fam` in a new project) triggers guided initialization that explains what's happening at each step: scanning files, building context, detecting conventions. Not a wall of output — step-by-step with confirmation. First `fam plan` includes brief orientation. Progressive hint system shows slightly more verbose output with inline guidance during first ~5 sessions, then fades. Early planning questions framed as knowledge acquisition with visible trend metrics.

### Design Opportunities

1. **Live activity view (`fam watch`)** — A structured real-time display of what the agent is currently doing: which file it's reading, what it's writing, tests running, validation in progress. Formatted as a live-updating status display, not a spatial simulation. Shows enough to give ambient awareness ("something is happening, it's on the right track") without demanding attention. Must work in a narrow tmux split. Designed after core command output is solid.
2. **Project health map** — A dashboard element in `fam status`: a grid where each block represents a project file. Color = relationship with Familiar (gray: untouched, blue: indexed in context, green: modified by completed task, orange: currently active, red: involved in failure). Over weeks, the green spreads — a visual record of Familiar's growing understanding of the codebase. A simple data visualization, not a spatial metaphor.
3. **Progressive disclosure** — Daily commands front and center. Power features discoverable through subcommands, flags, and `fam --help`. Context maintenance runs automatically; manual invocation is rare.
4. **Self-healing as default, triage as UX** — BEAM/OTP supervision means automatic recovery. `fam status` shows triaged results with three tiers. Self-repaired items invite review. The user's attention goes only where it's needed.
5. **Context trust indicators** — Simple health signal in `fam status`. Green/amber/red. Drill-in available; most won't need it.
6. **Thesis comparison view** — Side-by-side outputs from different providers and ablation runs via `fam review #N`. Makes thesis validation a first-class UX experience.
7. **The familiar learns visibly** — Planning that visibly improves. As context grows, repeat questions disappear, novel clarifications become sharper, specs arrive with more verified assumptions. The user can feel the familiar getting smarter. This is both a UX feature and a thesis validation signal.
8. **Onboarding that fades** — Guided first-run, oriented first-plan, progressive hints. The scaffolding removes itself. By session 5, the user sees the same clean interface a power user sees. No "beginner mode" toggle — just graceful maturation.

## Core User Experience

### Defining Experience

The core experience of Familiar is the **intent-to-spec transformation**. Everything downstream — task decomposition, execution, validation — is mechanical. The spec is the creative and intellectual fulcrum. If the spec is good, `fam do all` is a confident act. If the spec is bad, no amount of self-validation saves the output.

**The core loop:**

1. User expresses intent in natural language (`fam plan "..."`)
2. System generates a thorough spec — verified assumptions, discovered edge cases, conventions applied, conflicts flagged
3. User reviews the spec in the browser (rendered LiveView UI with approve/edit/reject) or optionally in `$EDITOR` via `--editor` flag
4. System decomposes into tasks and executes

Steps 1-3 are where user attention lives. Step 4 is where the system earns trust by delivering on what the spec promised. The UX must make steps 1-3 feel rigorous and fast, and step 4 feel reliable and unattended.

**What "good" looks like for a spec:**
- Demonstrates the system did its homework — not verbose, but thorough
- Verified assumptions cite their sources ("Queue table has user_id and completed_at ✓ — verified in db/migrations/003_queue.sql")
- Edge cases the user hadn't considered are surfaced ("Note: current session middleware doesn't handle expired tokens — spec includes token refresh")
- Project conventions are visibly applied ("Following existing pattern: handler in handler/recently_played.go, repository in db/recently_played_repo.go")
- Potential conflicts with existing code are flagged before execution, not discovered during
- Unverified assumptions are explicitly labeled so the user knows where the system is guessing
- Readable as raw plain-text markdown in any editor (format rules defined in the planner role file, not the UX spec — configurable by the user)

**What "bad" looks like for a spec:**
- Generic output that could apply to any project
- Assumptions stated without verification status
- Conventions ignored or contradicted
- Edge cases left to the implementation phase to discover
- Too brief (user can't evaluate) or too verbose (user won't read)

### Platform Strategy

**Hybrid model: CLI + localhost LiveView web UI**

The CLI is the control surface — where the user issues commands and drives the workflow. The web UI is the observation and review surface — where the user reads, evaluates, and interacts with rich content. They are complementary, not competing. Every operation works from the terminal alone; the web UI enhances but never replaces.

| Action | CLI (control) | Web UI (observe/review) |
|---|---|---|
| Plan a feature | `fam plan "..."` | — |
| Review/edit spec | `fam plan` opens browser to rendered spec | Rendered markdown, inline editing, approve/reject buttons |
| Execute tasks | `fam do`, `fam do --all` | — |
| Watch execution | `fam watch` (terminal fallback) | Live activity feed with LiveView streaming |
| Check status | `fam status` (quick pull, <1 second) | Dashboard with triage, health map, context health |
| Review task output | `fam review #N` | Visual diff, side-by-side, context injection log |
| Fix failures | `fam fix #N` (conversation in terminal) | Triage view → click to fix → opens terminal flow |
| Search context | `fam search "..."` | Browse/filter context store visually |

**Technology alignment:** Phoenix LiveView serves the web UI from the same BEAM process as the daemon. No separate server, no JavaScript build pipeline, no API layer. LiveView processes subscribe to the same PubSub events as the daemon — real-time updates are native, not polled. The technology choice and UX aspiration are naturally aligned.

**Zero-config web UI:** The daemon serves the web UI automatically on a localhost port. `fam plan` generates a spec and opens the browser to the rendered review page. No setup, no `fam ui start`. First experience should feel like magic — type a command, a rendered spec appears in your browser.

**Environment constraints (CLI):**
- Must work in half-screen terminal pane and narrow tmux splits
- Must work in integrated terminals (VS Code, JetBrains, etc.)
- All output legible at 80 columns minimum, optimized for 120 columns
- `$EDITOR` fallback via `--editor` flag for headless/SSH environments

**Notification model:**
- OS-native system notifications: auto-detect `terminal-notifier` (macOS) or `notify-send` (Linux)
- Configurable in `fam config` — notification provider, enable/disable
- Fallback: no notifications if no provider detected (user pulls with `fam status`)
- Escape hatch: `fam status --json` for custom integrations (ntfy, Slack, webhooks)

**Output format contract:**
- Every command supports `--json` (global flag, platform API)
- Every command supports `--quiet` (minimal output for scripting)
- Pretty-printed terminal output is the default
- Output format is an interface contract tested in CI

**Offline capability:**
- Fully functional with local Ollama provider (no internet required)
- Web UI is localhost — no internet, no cloud, no account
- Frontier provider (Anthropic) requires internet, used only when explicitly requested

### Effortless Interactions

**Things that should feel invisible:**
- Context injection — the user never thinks about it. Context quality shows up as spec quality, not as a separate interaction
- Self-repair — failures that the system can fix are fixed before the user sees them. The user only sees the triage result
- Convention following — generated code matches project patterns without the user specifying them. Verified in the spec, confirmed in the output
- Context maintenance — hygiene loop runs automatically. `fam context --refresh` exists for rare manual use
- Web UI availability — the browser just opens when needed. No setup, no configuration, no "start the server"

**Things that should feel fast:**
- `fam status` — returns in <1 second, parseable in <5 seconds visually
- `fam plan` to spec — for clear intents with rich context, the spec should appear in the browser in under 30 seconds with zero questions
- Spec review — browser opens immediately to a rendered, interactive document. No loading spinners
- `fam do` — command returns immediately. Execution is background. Feedback is via web UI dashboard (opt-in) or `fam status` (pull) or system notification (push)

**Things that should feel thorough:**
- Spec generation — thoroughness is the primary trust signal. Verified assumptions, cited sources, edge cases, conventions applied
- Init scan and convention discovery — the first proof of context quality. Brief summary shows what the system learned
- Error triage — failures explained, not just reported. What broke, what was reverted, what's blocked, what self-repaired

### Critical Success Moments

**"Aha" moment: First spec rendered in the browser.**
The user runs `fam plan` for the first time. Their browser opens to a beautifully rendered spec with verified assumptions highlighted green, unverified flagged amber, project conventions shown inline, edge cases called out. This is the moment they think "okay, this is different from every other AI tool." The rendered spec experience — not the terminal output — is where the product makes its first impression.

**Confidence moment: First successful `fam do --all`.**
The user approves a spec in the browser, runs `fam do --all`, and comes back to completed tasks. System notification tells them it's done. `fam status` or the web dashboard shows all green. The code looks like they wrote it. Trust-in-specs converts to trust-in-execution.

**Compounding moment: The familiar learns.**
After 10-15 tasks, repeat questions disappear. Novel clarifications become sharper and more targeted. Specs arrive with more verified assumptions. The system is visibly learning — it knows the project better each session.

**Recovery moment: First self-repaired failure.**
A task fails, the system retries, it works. The user sees "🔧 self-repaired" in triage and checks the diff — it's fine. Trust in unattended execution deepens.

**Feature recovery moment: `fam fix --feature`.**
The user realizes a whole feature spec was flawed. `fam fix --feature accounts` reverts all file changes via Familiar's internal snapshots (not git — the working directory returns to pre-feature state, git history untouched). A planning conversation opens pre-loaded with failure context. New spec avoids the same mistakes. The system learned from its own failure — demonstrating the value proposition.

**Make-or-break: Bad spec → bad code → lost time.**
If the spec misses something fundamental and the user only discovers it after execution, they've lost time. Spec quality is existential. Every UX decision about planning should be evaluated against: "does this make bad specs less likely?" The browser-rendered spec review with interactive approve/reject is the primary defense.

**Pre-commit boundary:**
After completed features, the UX surfaces uncommitted status explicitly: "Feature: accounts — 15/15 tasks complete. Changes are uncommitted." This is the boundary between "Familiar can revert this" (pre-commit, filesystem snapshots) and "you'll need git" (post-commit). `fam review` is the gate between those two worlds.

### Experience Principles

1. **The spec is the product.** The spec is where the user's intent meets the system's knowledge. It's the artifact the user evaluates, edits, and approves. Execution is downstream. Spec quality determines whether the tool is worth using.
2. **Thoroughness over speed in planning, speed over thoroughness in execution.** The user wants a thorough spec. They want fast, unattended execution. Don't optimize planning for speed at the cost of spec quality. Don't slow execution with confirmations.
3. **Show your work in the spec, hide your work in execution.** The spec visibly demonstrates reasoning: verified assumptions, cited sources, applied conventions, flagged conflicts. Execution is invisible — dispatch and walk away. The contrast is the trust model.
4. **Browser for reading, terminal for doing.** The web UI is where you evaluate, review, and observe. The CLI is where you command, fix, and configure. Each surface does what it's best at. Neither replaces the other.
5. **Edit in the user's environment, not ours.** Spec review defaults to the browser (rendered, interactive). `--editor` flag opens `$EDITOR` for users who prefer raw markdown or are in headless environments. The system adapts to the user's workflow.
6. **First impressions compound.** Init convention discovery is the first proof of context quality. First rendered spec is the first proof of planning quality. First `fam do --all` is the first proof of execution quality. Front-load quality into early interactions.
7. **Recovery demonstrates the value proposition.** `fam fix --feature` reverts file changes (not git), re-enters planning with failure context injected, and generates a corrected spec. The system learns from its own mistakes. Recovery isn't just damage control — it's a thesis validation signal.

## Desired Emotional Response

### Primary Emotional Goals

**The wizard and the familiar.** The user is the wizard — they hold the vision. Familiar is the familiar — proactive, knowledgeable, capable. The familiar doesn't just execute orders; it clarifies the vision, anticipates needs, and surfaces things the wizard hadn't considered. Software appears almost by magic — not because it's fast, but because it *fits*. The code matches conventions, follows patterns, respects architectural decisions. It looks like the wizard wrote it themselves. The magic is in never needing to rework what the familiar produced.

**Primary emotion: Empowered mastery.** The user feels like they have capabilities beyond what a solo developer should have. They describe a hazy vision and the familiar sharpens it into reality. The gap between "what I imagined" and "what I got" shrinks to nothing.

**Secondary emotion: Trust in a proactive partner.** The familiar doesn't wait to be told everything. It discovers conventions, surfaces edge cases, flags conflicts — then asks: "did you mean this?" The user trusts the familiar not because it's obedient, but because it's competent and curious. It makes the user think "oh, good point" more often than "I already told you that."

**Differentiating emotion: "You have to try this."** The moment a developer tells another developer about Familiar isn't when it's fast. It's when they review generated code and realize it followed a naming convention they never explicitly stated. Or when the spec catches a database conflict they would have missed. The magic is in the fit — code that doesn't need rework. That's the story they tell.

### Emotional Journey Mapping

| Stage | Desired Emotion | What Creates It |
|---|---|---|
| **Discovery** | Curiosity + skepticism | "Another AI coding tool?" — but the local-first, sovereign positioning is intriguing |
| **First init** | Impressed recognition | Convention discovery shows the system *sees* the project. Brief summary reflects back what the user knows about their own codebase. "It gets my project." |
| **First plan** | Collaborative sharpening | The familiar asks smart novel questions that make the user think harder about their own intent. The hazy vision gains edges. The rendered spec in the browser shows verified assumptions, cited sources, applied conventions. "It did its homework." |
| **First execution** | Quiet amazement | Code appears that follows conventions, reuses existing modules, handles edge cases from the spec. It looks like the user wrote it. The gap between vision and reality is small. |
| **Daily use** | Comfortable reliance | The familiar knows the project better each session. Novel questions still appear (valuable), repeat questions never do (the system learned). Dispatch and walk away with confidence. |
| **Overnight run** | Freedom | Wake up to completed work. Triage shows mostly green. The few items needing attention are clearly explained. The weekend morning belongs to the user, not to code review. |
| **Failure** | Calm competence | Something broke but the familiar already tried to fix it. What it couldn't fix is clearly explained. Recovery is one command away. The system learned from the failure. Not frustrating — the familiar handled what it could and brought only what it couldn't to the wizard. |
| **Recovery** | Reinforced trust | `fam fix` re-enters planning with failure context. New spec avoids the same mistake. The familiar got smarter. "It won't make that mistake again." |
| **Over time** | Partnership | The familiar becomes an extension of the wizard's thinking. Novel clarifications feel like a second pair of eyes, not an interrogation. The user thinks in terms of "we'll build this" not "I'll tell it to build this." |

### Micro-Emotions

**Confidence vs. Confusion**
- Confidence built through: thorough specs with cited sources, rendered browser review with green/amber indicators, explicit pre-commit status
- Confusion prevented by: summary views with drill-down (never a wall of text), triaged results (never a raw error list), clear command mental model (intent-driven)

**Trust vs. Skepticism**
- Trust built through: verified assumptions in specs, convention adherence in output, self-repair with transparent reporting, the familiar never asking the same question twice
- Skepticism prevented by: distinguishing self-repaired tasks from first-attempt successes (inviting review), `fam review #N` for full post-task transparency, filesystem-level undo (not git) with explicit pre-commit boundary

**Accomplishment vs. Frustration**
- Accomplishment created by: completed features that pass tests and match conventions, visible learning curve (novel questions stay, repeats disappear), the overnight run that just works
- Frustration prevented by: spec-level recovery (`fam fix --feature`), never overwriting user's concurrent edits, never asking a question the system should already know the answer to

**Delight vs. Mere Satisfaction**
- Delight created by: the project health map showing green spreading over time, a spec that catches an edge case the user missed, system notifications confirming overnight runs completed, the familiar surfacing something you hadn't thought of
- Satisfaction is the baseline; delight is the differentiator. Satisfaction comes from correct code. Delight comes from code that *fits* without being told how.

### Design Implications

| Emotional Goal | UX Design Choice |
|---|---|
| **Wizard/familiar partnership** | Planning conversation is collaborative, not interrogative. Novel questions are welcomed; repeats are system failures. The familiar is proactive — it surfaces things, not just responds to commands |
| **Magic through fit** | Spec visibly demonstrates convention adherence and context awareness. Generated code follows patterns without being told. The user never has to explain their project twice |
| **Empowered mastery** | Complex capabilities (multi-task execution, dependency management, context maintenance) are handled by the familiar. The user makes high-level decisions; the system handles the mechanics |
| **Calm competence in failure** | Three-tier triage presents failures as handled situations, not emergencies. Self-repair is the default. Recovery is one command. The familiar brings only genuine decisions to the wizard |
| **Freedom through trust** | `fam do --all` + walk away. System notification when done. The user's time is freed for thinking, not monitoring. Overnight runs are a feature, not a risk |
| **Partnership over time** | The system visibly learns — repeat questions disappear, specs get more accurate, conventions are applied without reminders. The user can feel the familiar getting smarter |

### Emotional Design Principles

1. **The familiar is proactive, not reactive.** It discovers, surfaces, anticipates, and clarifies. Novel questions that sharpen the user's vision are a feature. The familiar helps the user think, not just the user telling the familiar what to do.
2. **Repetition is the only unforgivable sin.** Asking a novel clarifying question is good. Asking the same question twice is a system failure. The emotional contract: "I will never waste your time re-explaining something you've already told me."
3. **Fit is the magic, not speed.** The user's emotional response to generated code should be recognition — "this looks like mine." Getting it right the first time saves more time than generating it fast. Every UX decision should optimize for output quality over output speed.
4. **Failures are handled situations, not emergencies.** The emotional tone of failure communication is calm competence. The familiar tried to fix it, here's what happened, here's the one thing it needs from the wizard. Not alarm bells — a status report from a capable partner.
5. **The wizard should feel powerful, not busy.** Familiar should reduce the user's cognitive load, not add to it. High-level intent in, working software out. The mechanics of planning, decomposition, execution, validation, and context maintenance are the familiar's job. The wizard's job is vision and judgment.

## UX Pattern Analysis & Inspiration

### Inspiring Products Analysis

**Telescope (Neovim)**
The fuzzy-find-anything paradigm. Files, grep results, buffers, symbols — all navigated through a single interaction model with instant preview. Learn one pattern (type, filter, preview, select), apply everywhere. Users who adopt Telescope can't go back — the interaction becomes muscle memory. The pattern extends beyond search: any list of items for selection can be a fuzzy-filterable picker.

**Obsidian**
No-bullshit markdown notes. Files in a folder. No proprietary format, no sync lock-in. The app adds value on top (backlinks, graph view, plugins) without compromising the plain-text foundation. You could delete Obsidian and your notes still work. The linking model is as powerful as the plain-text model — every note connects to its sources, creating a navigable knowledge web. Follow the trail, don't draw the map.

**Hyprland**
A tiling window manager that's opinionated and correct. Keyboard-driven, fast, deeply configurable. Speed and keyboard shortcuts create a feeling of directness — no mediation between intent and action. Zero visual noise. The zero-chrome philosophy applies to any interface: content, keybindings, and a status bar. Nothing else.

**systemctl status / Grafana**
Compact, triaged health displays. `systemctl status` shows service state in one screen: green/red, last few log lines inline. Grafana dashboards are color-coded panels scannable at a distance with drill-down on click. Together they define how a "morning after" status check should feel — triaged, actionable, one screen.

**Pair programming**
The closest analogy to Familiar's planning conversation. A knowledgeable colleague who's already read the code asks "have you thought about...?" — not "what is...?" The dynamic is collaborative, not extractive. Novel questions feel like a second pair of eyes.

**Video game tutorials (Celeste, Hollow Knight)**
The best tutorials teach through constrained play, not text boxes. Celeste teaches wall-jumping by putting you in a room where wall-jumping is the only way out. The first real use *is* the tutorial.

### Core Interaction Patterns

Four patterns govern all interaction design in Familiar. Every screen, command, and component should trace to one of these.

**Pattern 1: Unified picker for all selection (Telescope)**

Every interaction where the user selects from a list uses the same Telescope-style fuzzy finder: type, filter, preview, select. Same interaction model whether selecting a search result, a failed task to fix, a spec to review, or a file to inspect. Muscle memory transfers across every context.

Key properties:
- **Semantic search:** Results ranked by meaning, not string matching. Vector similarity under the hood, transparent to the user
- **Two-phase rendering:** Instant text matches (<50ms), then streaming semantic results (<200ms). The list populates immediately and gets *better*. Never show a loading state
- **Linked preview (Telescope × Obsidian):** Preview pane shows content *plus* the knowledge trail — linked specs, tasks, source files, related entries. `Tab` follows a link within the picker, navigating the knowledge graph without leaving the search interaction
- **Reusable component:** Same TUI picker in CLI (`fam search`, `fam fix`, `fam tasks`), same LiveView component in web UI. `Space` opens the picker from any web UI view
- **Search as diagnostic:** Search quality reflects context store quality. Track selection position and abandoned searches as health signals

**Pattern 2: Plain-text foundation with rich rendering (Obsidian)**

Every user-facing artifact is a plain-text file. Specs are markdown. Config is TOML. Roles and workflows are markdown. The web UI renders these beautifully but never owns them. Delete Familiar and everything is still readable.

Key properties:
- **Specs as markdown files** in the project directory, versioned with git, editable in any tool
- **Linked knowledge navigation:** Every artifact links to its sources — specs to context entries, entries to source files, tasks to specs. Links are clickable inline in the web UI. Trust through transparency: "I can see what the familiar knows and where it learned it"
- **Context entries are the exception:** They live in the vector database because semantic search requires it. But they should be exportable as plain text
- **Metadata via frontmatter, not database columns.** When specs need status, approval state, or linked task references — use markdown frontmatter. The file is the source of truth; the database indexes it

**Pattern 3: Keyboard-first, zero-chrome interaction (Hyprland)**

Every action is reachable by keyboard. The web UI has no sidebar, no top nav, no breadcrumbs. Content and a thin status bar showing context-specific keybindings. Speed is non-negotiable: any interaction >1 second breaks the feeling of directness.

Key properties:
- **View navigation model** — keyboard shortcuts jump between views:

| Key | View | Purpose |
|---|---|---|
| `Space` | Search | Telescope picker — search anything |
| `s` | Spec | Current spec review (approve/edit/reject) |
| `t` | Triage | Status dashboard, post-run triage |
| `w` | Watch | Live activity feed |
| `l` | Library | Knowledge store browser |
| `?` | Help | All keybindings on one screen |
| `Esc` | Return | Close overlay / return to previous view |

- **Vim-style navigation** within views: `j`/`k` to move, `Enter` to select/expand, view-specific actions shown in status bar
- **Configuration via `.familiar/config.toml`** — all keybindings remappable, colors configurable. Power users publish configs as dotfiles
- **Speed targets:** `fam status` <1 second. Search results appear <50ms. Web UI view transitions instant. No loading spinners for routine operations

**Pattern 4: Triaged dashboards for understanding (systemctl / Grafana)**

When the user needs to assess state (not select something), show a structured, glanceable dashboard. Color-coded, scannable at a distance, drill-down available.

Key properties:
- **Three-tier triage** after unattended runs: ✅ completed / 🔧 self-repaired / ❌ needs input. Color-coded sections with inline summaries
- **One screen, no scrolling** for the overview. Detail available on demand
- **Context health** shown as a simple signal: green/amber/red with entry count, staleness ratio, retrieval performance
- **Feature-level grouping** — triage organized by feature, not flat task list. "Accounts: 12/15 ✅, 2 🔧, 1 ❌"

**The distinction between patterns 1 and 4:** Pickers are for *acting* (selecting, navigating, deciding). Dashboards are for *understanding* (assessing state, triaging, monitoring). Never force the user to search when they need an overview, or scroll a list when they need to find one item.

### Anti-Patterns to Avoid

Four non-obvious traps that are tempting and likely during implementation:

**1. Different interaction models for similar actions**
It's easy to build search, task list, and fix selection as separate components with different UX. Then the user has to remember which mode they're in. If `fam search` uses fuzzy matching but `fam tasks` uses exact filtering, consistency is broken. Every picker must use the same Telescope-style interaction.

**2. Latency masked by loading spinners**
Semantic search adds 100-200ms. The temptation is to add a spinner. Don't. Use two-phase rendering: show instant text matches first, stream semantic results in. The user sees results getting better, not a blank screen getting populated. Any routine interaction >1 second breaks directness. Optimize or rethink the interaction.

**3. Traditional web navigation in LiveView**
The first `mix phx.gen.live` will scaffold a conventional layout with navbar and sidebar. Delete it. Phoenix generators assume you're building a web application. Familiar's web UI is a rendered document with keyboard navigation. Every default Phoenix layout decision must be reconsidered against the zero-chrome principle. This is the most likely trap because the tooling actively pushes you toward it.

**4. Specs in the database**
The temptation comes when you need spec metadata — approval status, linked tasks, execution state. The answer is markdown frontmatter, not database columns. The spec file is the source of truth. The database can *index* frontmatter for fast queries, but never *own* the data. The moment specs live in the database, you've violated the Obsidian principle — the user can no longer `cat` their spec, edit it in vim, or version it with git without going through Familiar.

### Design Inspiration Strategy

| Design Challenge | Primary Pattern | Source |
|---|---|---|
| CLI info density | Unified picker (selection) + Triaged dashboard (overview) | Telescope + systemctl |
| Live execution | Structured activity feed + triaged dashboard | systemctl + Grafana |
| Planning | *Experience pattern:* pairing mindset | Pair programming |
| Error triage | Triaged dashboard (three-tier) | systemctl + Grafana |
| Trust | Plain-text foundation + linked knowledge | Obsidian |
| Composability | Plain-text foundation + `--json` | Obsidian + Hyprland |
| Command surface | Unified picker (one pattern everywhere) | Telescope |
| Web UI philosophy | Keyboard-first zero-chrome + keyboard navigation | Hyprland |
| Search | Unified picker with linked preview | Telescope × Obsidian |
| Onboarding | *Experience pattern:* first use is real use | Celeste |

## Design System Foundation

### Design System Choice

**Custom minimal CSS.** Browser reset + hand-written styles + design tokens as CSS custom properties. No framework. No component library.

**Why:** The web UI has 5-6 keyboard-navigated views with zero chrome. The primary rendering task is markdown with semantic annotations. A CSS framework would impose navigation chrome, mouse-first patterns, and component opinions that all conflict with Familiar's design principles. For this surface area, custom CSS is less maintenance than fighting a framework.

**What not to do:** Don't reach for Tailwind, Pico, or a component library when the CSS gets tedious. The tedium is bounded (5-6 views, <500 lines). A framework's opinions are unbounded. This decision was made with eyes open about the accessibility cost — focus management and ARIA patterns must be hand-implemented. Define them upfront, test with a screen reader early.

### Visual Direction

**Terminal-adjacent dark minimal.** The web UI feels like a beautifully typeset terminal output — monospace where appropriate, dark background, high-contrast text. Color is used only for meaning, never for decoration.

Not brutalist (too stark), not material (too soft), not glassmorphic (too decorative). Clean, dark, purposeful. Sits alongside neovim, tmux, and hyprland without visual friction.

### Color System

All color carries meaning. No decorative color. Three semantic colors (green/amber/red) carry aligned meanings across categories — the user disambiguates by view context, not by color variation.

**Color temperature: Neutral cool grey.** Backgrounds are near-neutral grey with a subtle cool lean — less blue than GitHub Dark, neutral enough to coexist with diverse terminal themes (Catppuccin, Tokyo Night, Gruvbox, Nord). The accent blue provides the cool tone; backgrounds don't.

**Semantic palette:**

| Category | States | Color Intent |
|---|---|---|
| **Triage** | complete / repaired / needs-input | green / amber / red |
| **Context health** | healthy / stale / critical | green / amber / red |
| **Knowledge state** | untouched / indexed / modified / active / failed | grey / blue / green / amber / red |
| **Verification** | verified / unverified | green / amber |
| **UI surfaces** | bg / surface / border | Very dark grey / slightly lighter grey / subtle grey |
| **UI text** | primary / muted | Near-white / mid-grey |
| **UI interactive** | accent / focus | Blue |

Dark theme only. Light theme achievable via ~6 color overrides in `.familiar/config.toml` but not designed or supported. All tokens defined as CSS custom properties, all overridable.

### Typography

**Two font stacks, no bundled fonts:** Monospace (user's configured mono → system monospace) for tool elements — titles, code, file paths, trail output, status bar. Prose (system-ui, sans-serif) for reading — spec body, context entries, documentation. No web fonts shipped; the UI uses what's already on the user's system.

**Dual density model:** The UI has two density contexts because tool views and reading views have different needs.

- **Tool density** (triage, task lists, status, trail, status bar): Tight sizing (~0.8-0.85rem base), tight line height (~1.3). htop/lazygit aesthetic. Every pixel earns its place
- **Reading density** (spec body, context entries, documentation): Comfortable sizing (~0.95rem base), relaxed line height (~1.5-1.6). The user reads spec prose for 2-3 minutes — it must be comfortable for sustained reading

Information hierarchy comes from weight and color, not dramatic size jumps. Feature titles are the largest element (bold mono). Body text and tool text are close in size. The difference between views is line height and spacing, not font size.

### Spacing & Layout

**Density follows the dual model.** Tool views use approximately half the typical web spacing scale — dense, scannable, more information on screen. Reading views use comfortable spacing for sustained reading.

**Spacing tokens:** Five-step scale (xs through xl) with each step roughly doubling. Exact values tuned during implementation. The full scale is approximately half typical web design system spacing.

**Layout principles:**
- **Tool views are full-width.** Triage, task lists, status, trail — content runs edge-to-edge minus view padding. These views benefit from the space
- **Reading views have max-width ~72ch.** Spec prose, context entries — line length capped for readability. The user's window width controls whitespace around the prose, not line length
- **Single-column layout.** No sidebars, no split panes except the search picker overlay (the only multi-column element)
- **Status bar as sole chrome.** Fixed bottom, height derived from text size + padding. Everything else is content
- **Vertical stacking.** Scroll within a view, keyboard shortcuts between views

### Accessibility

**Contrast:** Primary text on background ≥7:1 (targeting AAA). Muted text ≥4.5:1 (AA). Semantic colors (green/amber/red) ≥4.5:1 and distinguishable for color-blind users — ✓/⚠/❌ symbols carry meaning independently of color.

**Keyboard:** All interactive elements reachable. Visible focus indicators (accent-blue outline). Focus order follows visual order. No keyboard traps — `Esc` always exits.

**Screen reader:** Status bar as `role="status"` with live region. Picker overlay as `role="dialog"`. Verification marks have aria-labels ("verified"/"unverified"). Triage blocks have full status text labels.

**Animation:** No decorative animation. Data-driven updates are instant — lists re-sort, colors swap, content appears. No transitions, fades, or easing. Respects `prefers-reduced-motion` by default because there's nothing to reduce.

### Spec View Reference

The spec review page is the most important view — where the user evaluates the familiar's work and decides whether to proceed. Its design defines the visual vocabulary for the entire application.

**What the user sees (top to bottom, nothing else):**

1. **Feature title:** Large, monospace, bold. Reads like a commit message header.
2. **Metadata line:** Trust summary in muted text — `Generated 2026-03-28 · 8 verified · 2 unverified · 3 conventions applied`. The spec's vital signs at a glance.
3. **Spec body:** Rendered markdown at reading density, max-width ~72ch. Three typographic voices:
   - *Spec prose:* System sans-serif, comfortable line-height, the bulk of the page
   - *Annotations:* Inline verification marks (✓ green / ⚠ amber) with source citations in muted italic. Visually secondary
   - *Code references:* Inline monospace for file paths, table names, migrations
4. **Status bar:** Fixed bottom — `a: approve · e: edit · r: reject · d: diff · c: context · Space: search · ?: help`

**Verification display — two levels:**
- **Inline:** ✓ or ⚠ symbol at the start of a claim, source citation in muted italic: `✓ users table has email column — verified in db/migrations/001_init.sql`
- **Block:** Green or amber left-border for grouped verified/unverified content

**Knowledge links:** Source citations are navigable but styled as annotations — muted italic, dotted underline on keyboard focus only. Discovered via `Tab`, not visual loudness.

**Convention annotations:** Muted italic — `Following existing pattern: handler/song.go, handler/queue.go`.

**Secondary views (one keypress away, not shown by default):**
- `d` — diff from previous version
- `c` — all context entries that influenced the spec
- Planning conversation history

The spec view needs only: two fonts, three annotation treatments (green/amber/muted), a subtle link style, and a status bar. This visual vocabulary defines every other view.

### Interaction Principle

All interactive elements are keyboard-triggered actions. The status bar (fixed bottom, persistent across all views) is the universal affordance — it shows available actions for the current context. No floating buttons, no click targets, no hover states for interaction. Visual feedback comes through content changes, not UI widget animations.

**Status bar actions include view-specific transitions:**
- Approve (`a`) → decomposition begins, view transitions to task list or notification
- Edit (`e`) → opens spec in `$EDITOR` or in-browser editor; view refreshes on save
- Reject (`r`) → spec discarded, returns to planning conversation

Each view has its own action set shown in the status bar. Global actions (`Space` for search, `?` for help, `Esc` for return) are available everywhere. View-specific actions appear only in their context.

## Defining Experience

### The User Story

*"I described a feature in one sentence. The system checked my database schema, found a session bug I didn't know about, applied my naming conventions, and produced a spec I trusted enough to run overnight."*

The defining experience is the moment the familiar demonstrates it *knows your project* — specifically, not generically. It checked the things you would have checked, caught something you missed, and produced a plan that fits.

### What Familiar Replaces

The pain is in the rigor. Discovering all requirements, verifying assumptions against the codebase, finding the right patterns, decomposing into estimable subtasks. This is the tedious, high-value work between "I have an idea" and "I'm writing code" — the work that, when skipped, leads to rework. The familiar does this labor. The wizard keeps the creative act of deciding *what* to build.

Users bring existing mental models: natural language intent (commit messages, issue descriptions), plan-then-execute workflows (PRs, CI/CD), review-before-commit (approval gates). Familiar builds on these patterns, not against them.

### The Streaming Reasoning Trail

The discovery phase streams a structured activity trail to the terminal. Each line corresponds to actual tool use (file read, context query, verification check) — not a reconstructed summary.

```
Planning: "add user accounts"
  Checking context store... 12 entries relevant
  Reading handler/session.go
    → Checking: does session middleware handle token refresh? → No
    → Including refresh logic in spec
  Reading db/migrations/001_init.sql
    → Verified: users table has email, hashed_password, inserted_at
  Checking: rate limiting for login attempts
    → No existing pattern found → flagging as unverified
  Applying conventions: handler naming, repo pattern, template structure
  Questions: 0

Spec ready → opening browser
```

**The trail is a trust accelerator, not a dependency.** The spec must stand alone — verification marks, metadata, cited sources communicate everything the trail would have. The trail makes trust build faster for users who watch, by setting expectations and reducing anxiety.

| Function | What It Does |
|---|---|
| **Reasoning display** | Shows the familiar's intent and conclusions, not just file access |
| **Spec preview** | User watches the spec being assembled; browser review has context |
| **Onboarding tool** | First-time users learn the verification language by watching it built |
| **Audit log** | The trail *is* the log. `fam log --feature accounts` replays it |

Intervention channel (typing to steer mid-generation) is a potential future capability. MVP ships with a read-only trail — the edit flow (`e`) covers post-generation adjustments.

**Design rules:** One line per conclusion (~10-20 lines per spec). Heartbeat if no output for 5+ seconds. Trail and spec must be consistent. Test at 80 columns. Progressive hint on first use, fades after ~3 plans.

### Dispatch Confidence = Leverage

The primary success criterion: would the user `fam do --all` and walk away?

Dispatch confidence is the measurable proxy for *leverage*. The user's willingness to dispatch and walk away is the moment they multiply themselves — thinking about the next feature while the familiar builds the current one. Familiar's value isn't faster coding; it's parallel work. One person, output of two.

This is compound:
- **Spec confidence** = "the plan is good" — earned through thorough specs with verified assumptions
- **Execution confidence** = "implementation will fit" — earned through successful past executions and self-repair
- **Leverage** = both together = "I can think about the next thing while this gets built"

### Critical Failure Modes

| Failure | Severity | Mitigation |
|---|---|---|
| First spec is generic (user story never happens) | Critical | Init scan must produce enough context for project-specific first spec. If not, thesis fails |
| Trail reasoning is wrong | High | Trail reflects actual tool use. Verification marks in spec are ground truth |
| False dispatch confidence (subtle flaw → bad overnight code) | High | Self-validation is the safety net. Triage manages expectations |
| Spec requires trail context to understand | Medium | All trust signals must be in the spec itself. Test by reviewing without watching trail |

## Design Direction Decisions

### View Design Decisions

**Triage view: Grouped list, worst-first sort, everything visible**

After a run, everything is shown — failures sort to the top, successes after. Sort order at every level: ❌ first, 🔧 second, ✅ last.

```
accounts (3/5 ✅  1 🔧  1 ❌)
  ❌ #5  Add login handler               [failed on subtask 3/5: adding test]
  🔧 #4  Add session middleware          [retried: router pattern mismatch]
  ✅ #1  Create users table migration
  ✅ #2  Add user repository
  ✅ #3  Add registration handler

search (4/4 ✅)
  ✅ #6  Add FTS5 virtual table
  ✅ #7  Add search repository
  ✅ #8  Add search handler
  ✅ #9  Add Datastar search component
```

For large runs, `fam status --summary` shows headers without task lines.

**Search picker:** Overlay in web UI (Telescope model, context preserved). Full-view in CLI (fzf model). Same behavior, platform-dependent presentation.

**Streaming trail:** Inline terminal output with summary line at completion. Full specification in Defining Experience section.

### Work Hierarchy

**PRD Delta:** The PRD defines Feature → Task (two levels). The UX spec adopts Epic → Group → Task → Subtask (four levels). Requires PRD reconciliation.

The intermediate level is called "Group" (not "Story") — the familiar produces functional groupings, not user stories with acceptance criteria.

**Four levels, two decomposition times:**

| Level | Concept | Decomposed When |
|---|---|---|
| **Epic** | The user's intent | User initiates via `fam plan` |
| **Group** | Functional slice of the epic | Planning time — by the familiar |
| **Task** | Independently executable work item | Planning time — by the familiar |
| **Subtask** | Implementation step producing an artifact | Execution time — by the agent |

Subtasks are discovered during execution, not planned upfront. You don't know them until the agent starts the work. A subtask is a work item that produces an artifact (file created, test written) — not an activity (file read, pattern checked).

**Design rules:**
- Flexible depth: trivial features skip groups (Epic → Tasks). Simple tasks have no subtasks. Empty levels collapse in the UI
- Depth indicator: text header shows position — `Epic: User Accounts > Group: Authentication`
- Live status, stable sort: badges update in real-time via LiveView, rows don't re-sort. Re-entering the view refreshes sort
- Subtask visibility in triage: annotations include subtask progress — `[failed on subtask 3/5: ...]`
- Status roll-up: any failed subtask = ❌, self-repaired = 🔧, all green = ✅. Same at every level
- CLI commands need updating for four levels — exact design in PRD reconciliation

**`fam fix` at any level:** `fam fix #5` fixes task #5 (numeric ID). `fam fix` without argument opens the Telescope picker — user searches and selects what to fix. Picker results show hierarchy level as context: `[epic] User Accounts`, `[group] Authentication`, `[task] #5 Add login handler`.

## User Journey Flows

### Journey: First-Run Onboarding

The user runs `fam` in a project directory for the first time. The system genuinely learns the project — no demo, no simulation.

```
No Familiar project found. Initializing...

Checking environment:
  Ollama at localhost:11434 ✓
  Embedding model: nomic-embed-text ✓
  Coding model: qwen2.5-coder:14b ✓
  Frontier fallback: not configured (add with fam config)

Scanning project files...
  Indexed: 64 (Go source, templates, SQL migrations)
  Skipped: 19 (go.sum, .git, vendor)

Discovered conventions:
  Package structure: handler/, model/, db/, tmpl/, static/ (64/64 files)
  Naming: snake_case files, CamelCase exports (61/64 files)
  DB pattern: repository pattern via db/ package (4 repos found)
  Template engine: Datastar templates in tmpl/ (12 templates)
  Error handling: wrapped errors with fmt.Errorf (23 call sites)

Review conventions? [y: edit, Enter: accept]
```

```
✓ Project initialized. 64 files indexed, 5 conventions stored.

Try: fam plan "describe a feature" — your spec will appear in the browser for review
```

**Key decisions:**
- Environment check first — fail fast if Ollama isn't running
- Convention discovery shows evidence (counts alongside conclusions) — first trust moment
- Any `fam` command triggers init if `.familiar/` doesn't exist
- Init is atomic — completes fully or leaves no trace
- Web UI not involved — browser opens for the first time on `fam plan`
- Target: under 5 minutes. Large/complex projects may need adapted onboarding (post-MVP concern)

### Journey: Chain Failure Recovery

The user dispatched `fam do --all` overnight. The system self-repaired what it could. The user sees only what needs their judgment.

```
fam status

User Accounts (13/15 ✅  1 🔧  1 ❌)
  ❌ #5  Add session middleware          [failed: ambiguous session strategy — needs user decision]
  🔧 #8  Add profile handler            [self-repaired]
  ⊘ #10 Add session expiry             [blocked by #5]
  ⊘ #11 Add remember-me                [blocked by #10]
  ✅ #1  Create users table migration
  ... (8 more ✅)

Last run: 2026-03-28 02:47 — completed in 1h 23m
Self-repaired: 3 tasks
Context: 247 entries, healthy
Backup: 2026-03-28 02:47 (auto, after last batch)
```

Triage states and sort order defined in Design Direction Decisions. Blocked (`⊘`) is a display state in muted grey — pending work, not a failure.

**The user fixes the one thing that needs judgment:**

```
fam fix #5

Fix: #5 Add session middleware
  Failed: ambiguous session strategy
  Context shows two patterns:
    → Cookie-based sessions (handler/auth.go, 3 references)
    → Token-based sessions (handler/api.go, 2 references)

Which approach?
  → Cookie-based (consistent with existing web handlers)
  → Token-based (consistent with API handlers)
  → Other (describe your approach)
```

User picks. `fam do --all` resumes with full autonomy — fix executes, blocked tasks unblock automatically. Done.

**Key decisions:**
- Triage shows only what needs human judgment — self-repaired tasks handled before the user arrives
- `fam fix` opens with failure analyzed, ambiguity identified, options proposed — the signature interaction
- `fam do --all` after fix behaves identically to initial dispatch
- "Self-repaired: 3 tasks" and backup status visible — the safety net is explicit

### Journey: Debugging Context (Rare Fallback)

Identical patterns to chain failure recovery, triggered by user observation rather than system triage. Rare by design — the system auto-refreshes stale context, retries with refreshed context on failure, and checks for duplicate code during validation. When autonomous repair isn't enough: `fam review #N` shows injected context with staleness flags. Fix via `fam fix` at the appropriate level.

### Journey Patterns

All journeys follow the bookend model: **set intent → absence → review results.** The user comes back to progress, with anything that needs them clearly flagged. Not perfection — leverage plus transparency.

**`fam fix` is the signature interaction** — the moment the familiar feels most like a familiar. Failure already analyzed, options proposed, user picks. The story users tell friends.

**`fam review` is a power tool, not a routine step.** Primary post-execution: `fam status` → commit or fix. Review is for curiosity and debugging.

**Autonomous first, manual fallback.** Context refresh, subtask retry, duplicate detection, multi-cycle recovery, provider failure pause — all handled before involving the user.

### Resilience: Edge Cases

| Scenario | Behavior | PRD Delta? |
|---|---|---|
| Ollama dies mid-init | Atomic — completes or leaves no trace | Yes |
| Ollama dies overnight | Retry with backoff, then pause. Resume when provider returns | Yes |
| Unattended file conflict | Save as `.fam-pending`. User resolves on return via `fam review` | Yes |
| SQLite corruption | Integrity check on startup. Auto-restore from backup | Yes |
| Any command before init | Triggers init automatically | Yes |
| Auto-backup | After each successful batch. Status in `fam status` | Yes |

## Component Strategy

### Component Inventory

All components are Phoenix LiveView components styled with custom CSS tokens. No external component library. Each component follows established patterns: keyboard-first, zero-chrome, tool density for dashboards, reading density for prose.

| Component | Views Used In | Interaction |
|---|---|---|
| **Status bar** | All | Persistent bottom bar, context-specific keybindings |
| **Search picker** | Overlay on any | Split pane (results + preview), `Space` to open, `Esc` to close |
| **Triage list** | Triage (`t`) | Grouped worst-first list, `j`/`k` navigation, `Enter` to drill |
| **Spec renderer** | Spec (`s`) | Rendered markdown with verification marks, knowledge links, metadata |
| **Work hierarchy** | Triage + drill-down | Depth indicator header, `Enter` to drill, `Esc` to back up |
| **Activity feed** | Watch (`w`) | Streaming structured output, live-updating |
| **Knowledge browser** | Library (`l`) | Browsable context entries with search, preview, and links |
| **Help overlay** | Any (`?`) | Full-screen keybinding reference, `Esc` to dismiss |

### Component Specifications

**Activity Feed (Watch View)**

The watch view shows what the familiar is currently doing — the web UI equivalent of the terminal streaming trail, but persistent and structured.

```
Watch — fam do --all (task 4/15)

Currently executing: #4 Add session middleware
  Group: Authentication

  Reading handler/auth.go
  → Checking existing auth patterns
  Reading db/migrations/003_sessions.sql
  → Verified: sessions table schema
  Writing handler/session.go
  → Applying convention: handler naming pattern

  Subtasks: 2/4 complete
    ✅ Read existing patterns
    ✅ Generate middleware code
    ◐ Run tests
    ○ Validate output

Previously completed:
  ✅ #1  Create users table migration     32s
  ✅ #2  Add user repository              1m 04s
  ✅ #3  Add registration handler         2m 11s

[Space: search  t: triage  s: spec  ?: help  Esc: close]
```

- Tool density — tight line height, monospace, every line informational
- Current task activity streams in top section, completed tasks stack below
- Subtask progress as checklist (✅ done, ◐ in progress, ○ pending)
- Updates in real-time via LiveView PubSub
- If nothing executing, shows last run summary
- No historical scrollback — that's `fam log`

**Knowledge Browser (Library View)**

Browse and inspect the context store. Used for curiosity, debugging, and trust-building.

```
Library — 247 entries, healthy

  Search: [                                        ]

  Recent entries:
    [decision]  Use cookie-based sessions for web auth     2026-03-28
    [fact]      Session table: id, user_id, token, exp     2026-03-28
    [convention] Handler naming: handler/{resource}.go     2026-03-15
    [gotcha]    Datastar templates need explicit IDs       2026-03-20
    [relationship] auth handler depends on session repo    2026-03-28

  Filter: [all] decision  fact  convention  gotcha  relationship

[Space: full search  d: delete  Enter: inspect  ?: help  Esc: close]
```

Entry preview (right pane on wide, below on narrow):

```
  Convention: Handler naming pattern
  Source: init-scan (2026-03-15)
  Freshness: ✓ all referenced files unchanged

  Handler files follow the pattern handler/{resource}.go
  with a corresponding {resource}_handler_test.go.

  Evidence: handler/song.go, handler/queue.go,
  handler/artist.go (3/3 consistent)

  Referenced by:
    → Spec: "Add user accounts" (assumption #4)
    → Task #3: Add registration handler
    → Task #4: Add session middleware
```

- Entries listed with type badge, one-line summary, date — tool density
- Inline search filters as-you-type (two-phase rendering, scoped to context entries)
- Type filter tabs toggle entry categories
- `Enter` shows full content with linked artifacts — same knowledge link model as spec view
- Browse-first (entries by recency) with search available — the user explores, not hunts

**Help Overlay**

Single-screen keybinding reference on `?` from any view.

```
Familiar — Keyboard Shortcuts

  Global
    Space     Search (Telescope picker)
    s         Spec view
    t         Triage view
    w         Watch view
    l         Library view
    ?         This help
    Esc       Close / back

  Spec View                     Triage View
    a   Approve spec              j/k   Navigate items
    e   Edit spec                 Enter  Drill into item
    r   Reject spec               Esc   Back up one level
    d   Show diff                 f     Fix selected item
    c   Show context used
    Tab Next knowledge link     Search Picker
    Enter Follow link             j/k   Navigate results
                                  Tab   Follow linked entry
  Watch View                      Enter Go to result
    (view only)                   Esc   Close picker

  Library View
    j/k   Navigate entries
    Enter Inspect entry
    d     Delete entry
    Tab   Cycle type filters
                                        [Esc to close]
```

- One screen, no scrolling — all keybindings fit
- Organized by view context
- Monospace, tool density — looks like a man page

### Implementation Strategy

All components share CSS custom property tokens, keyboard event handling via `phx-keydown`, real-time updates via Phoenix PubSub, and consistent focus management.

**Priority (by journey criticality):**

| Priority | Component | Why |
|---|---|---|
| 1 | Spec renderer | Most important view — where trust is built |
| 2 | Status bar | Required by every view |
| 3 | Triage list + work hierarchy | Morning-after experience |
| 4 | Search picker | Universal navigation |
| 5 | Help overlay | Discoverability |
| 6 | Activity feed | Ambient awareness, not critical path |
| 7 | Knowledge browser | Power tool, not daily workflow |

Components 1-5 for MVP. Components 6-7 follow shortly after.

## UX Consistency Patterns

### Feedback: Two-Layer Notification System

Feedback is split into two distinct UI elements with different temporal behavior.

**Layer 1: Global status indicator**

A conditional line above the status bar that appears only when there's a system-level state to communicate. When everything is healthy, it's invisible. When a problem exists, it appears and persists until the state resolves.

Normal (no global status — just the status bar):
```
[a: approve · e: edit · r: reject · Space: search · ?: help]
```

Error state (global status appears above status bar):
```
✗ Ollama unavailable — execution paused. Restart Ollama to resume
[a: approve · e: edit · r: reject · Space: search · ?: help]
```

- Lives in the root layout — follows the user across all view transitions
- Uses semantic colors for *state*: red = system problem, amber = degraded
- Appears and disappears based on system state — not user-dismissible
- The absence of a global status line *is* the healthy state

**Layer 2: Ephemeral toast messages**

Brief text above status bar and global status, auto-dismissing. Feedback for user actions.

| Type | Icon | Color | Example | Duration |
|---|---|---|---|---|
| Success | ✓ | Green | `✓ Spec approved — decomposing into tasks` | 3s |
| Info | → | Accent blue | `→ Opening spec in browser` | 3s |
| Warning | ⚠ | Amber | `⚠ Reverted 5 tasks in "Authentication" — replanning` | 5s |

- Stack if multiple appear (max 3, oldest dismissed first)
- Never steal keyboard focus
- `--json` mode: emitted as JSON events for custom notification handling

### Empty States

Empty views tell the user what to do next, framed in the wizard/familiar metaphor where it fits naturally.

| View | Empty State |
|---|---|
| Triage | "No tasks yet. The familiar is ready. Start with: `fam plan "..."`" |
| Watch | "Nothing running. Last run: [summary]. Start: `fam do --all`" |
| Library | "The familiar hasn't learned your project yet. Run `fam init` to introduce it." |
| Search | "No results for 'query'. Try broader terms." |
| Spec | "No spec in progress. Start: `fam plan "..."`" |

One sentence explaining the state + one sentence with next action. Tool density, muted text.

### Execution Sanity Check

`fam do --all` does not require confirmation. Before execution begins, a brief status line shows what's about to execute:

```
fam do --all

Executing: 15 tasks (User Accounts). 0 tasks from other epics.
```

Not a prompt — execution begins immediately. The user can `Ctrl+C` if something looks unexpected.

### Destructive Action Confirmation

Developer tools trust the developer. Only `fam restore` requires confirmation — it replaces the entire context store with an older snapshot.

Everything else executes immediately: approve, reject, edit, delete, fix at any level, `fam do --all`. Toasts confirm what happened. The fix conversation shows what will be reverted as part of its flow.

`fam restore` confirmation:
- Terminal: `Restore from 2026-03-27 backup? Current context store will be replaced. (y/n)`
- Web UI: global status line becomes the prompt: `⚠ Restore from backup? [y: confirm  Esc: cancel]`
- Default is cancel

### System Error Communication

System errors are infrastructure problems, distinct from task failures (triaged via ✅/🔧/❌).

| Severity | Example | Display | User Action |
|---|---|---|---|
| **Recoverable** | Ollama temporarily unreachable | Global status: `✗ Retrying (3/5)` → toast: `✓ Reconnected` | None |
| **Blocking** | Ollama down, retries exhausted | Global status: `✗ Ollama unavailable. Restart to resume` | Restart Ollama |
| **Degraded** | Disk space low | Global status: `⚠ Disk space low (2GB)` | Free disk |
| **Fatal** | SQLite corruption | Full-screen: what happened + recovery command | Run `fam restore` or `fam init --rescan` |

- Never show stack traces in the UI. User messages say what happened and what to do
- `fam log --system` is verbose — full technical detail for debugging. Available as `--json` for monitoring tools
- Fatal errors are the only time Familiar takes over the screen

## Responsive Design & Accessibility

### Responsive Strategy

**Desktop-only, but window-size responsive.** The web UI is localhost — no mobile, no tablet, no touch. But developers use tiling window managers, split screens, and narrow browser panes. The UI must work from a narrow vertical strip (400px) to a full-width monitor (2560px+).

**Three layout zones:**

| Zone | Width | Layout Adaptation |
|---|---|---|
| **Narrow** | 400px — 768px | Single column. Search picker stacks (results above, preview below, `Tab` toggles). Status bar truncates to keys only: `a · e · r · Space · ? for help`. Code blocks get contained horizontal scroll |
| **Medium** | 769px — 1200px | Single column with comfortable margins. Search picker side-by-side. Spec prose at max-width ~72ch centered. Primary design target |
| **Wide** | 1201px+ | Currently same as medium — extra width becomes margin. Current behavior, not a locked principle. Wide zone may gain features post-MVP (preview panes, side-by-side context). Use a CSS breakpoint, not just max-width |

**Key decisions:**
- No minimum width cutoff — degrades gracefully below 400px
- Search picker: side-by-side at medium+, stacked at narrow. Stacked shows one panel at a time, `Tab` toggles. LiveView JS hook detects viewport width for keyboard adaptation
- Tool density views are naturally narrow-friendly — single-column text lists at any width
- Reading density views use max-width ~72ch — at narrow, prose fills available space
- Status bar: narrow shows `a · e · r · Space · ? for help` (keys + help hint). Full labels at medium+. Help hint fades after ~3 sessions
- No horizontal page scrolling. Code blocks get `overflow-x: auto`

### Accessibility Summary

WCAG AA compliance target. Accessibility defined throughout the document, consolidated here.

**Color & Contrast:**
- Primary text on background: ≥7:1 (targeting AAA)
- Muted text on background: ≥4.5:1
- Semantic colors on background: ≥4.5:1
- Verification marks carry meaning via symbol, not just color

**Keyboard:**
- Primary input method, not an alternative
- Visible focus indicators (accent-blue outline)
- Focus order follows visual order
- No keyboard traps — `Esc` always exits
- Global shortcuts work from any view

**Screen Reader:**
- Status bar: `role="status"` with live region
- Global status indicator: `role="alert"`
- Search picker: `role="dialog"` with `aria-label`
- Triage states: aria-labels ("complete", "self-repaired", "needs input", "blocked")
- Verification marks: aria-labels ("verified", "unverified")
- Toasts: `role="status"` with `aria-live="polite"`

**Animation:** None. Data updates instant. `prefers-reduced-motion` respected by default.

**Testing:**
- Keyboard-only navigation testing during development
- Contrast validation against WCAG AA for all token colors
- Screen reader smoke test: **triage view** — most semantically complex (nested groups, four status types, drill-down, live updates). If triage works, everything else will
- Narrow window testing at 400px for all views
