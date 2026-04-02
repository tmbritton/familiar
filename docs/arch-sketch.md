# Anthill — Product Requirements Document

**Version:** 0.1 (Draft)  
**Status:** Pre-development  
**License:** AGPL-3.0

---

## Overview

Anthill is a general-purpose autonomous workflow executor for knowledge work. It consists of a long-running Elixir daemon that orchestrates a team of AI agents and a rich terminal UI for human interaction. Agents communicate via message passing on the BEAM, share memory through a searchable context store, and execute tasks using local and frontier LLM models.

The daemon is co-located with the codebase and performs all file operations directly. Clients are thin UI layers that connect over TCP — meaning the client can be a terminal, a mobile app, a browser, or an editor plugin. Work can be initiated and monitored from anywhere, including a phone, liberating developers from their keyboards.

The system is domain-agnostic by design. Agent roles, workflows, and skills are defined as markdown files — different domains are different directory configurations. Anthill ships with a software development configuration by default, but is equally suited to content creation, marketing, research, communications, or any repeatable knowledge work that happens on a computer.

The system is designed so that tasks are decomposed into small, well-defined units with rich injected context — enabling local models to perform competitively with frontier models for execution-level work.

---

## Design Philosophy

- **Small tasks, rich context.** Ambiguity is resolved before execution. Agents receive precise tasks with pre-loaded relevant context, minimizing LLM confusion and enabling local model viability.
- **Fault tolerance is structural, not implemented.** OTP supervision trees provide agent lifecycle management, crash recovery, and restart semantics without application-level error handling boilerplate.
- **Institutional memory compounds.** The context store accumulates knowledge across runs. Later agents benefit from earlier agents' discoveries automatically. A content system learns brand voice; a coding system learns codebase patterns.
- **Domain-agnostic core.** The orchestration layer knows nothing about software development, content, or any other domain. Domains are expressed entirely through role definitions, workflows, and skills — plain markdown files.
- **Boring technology.** SQLite, TCP, markdown files, standard OTP patterns. No frameworks beyond what Elixir/OTP provides.
- **One binary.** Users download a single executable. No runtime installation required.

---

## Architecture

### Components

```
┌─────────────────────────────────────────────┐
│              Burrito Binary                  │
│  ┌──────────────┐   ┌──────────────────────┐│
│  │  TUI Client  │   │   Elixir Daemon       ││
│  │  (Ratatouille│◀──│  ┌────────────────┐  ││
│  │   or Owl)    │TCP│  │ Task Supervisor│  ││
│  └──────────────┘   │  ├────────────────┤  ││
│                     │  │ Agent Processes│  ││
│                     │  ├────────────────┤  ││
│                     │  │ Context Store  │  ││
│                     │  │ (GenServer +   │  ││
│                     │  │  SQLite)       │  ││
│                     │  ├────────────────┤  ││
│                     │  │ MCP Client     │  ││
│                     │  │ Pool           │  ││
│                     │  └────────────────┘  ││
│                     └──────────────────────┘│
└─────────────────────────────────────────────┘
```

### Communication Protocol

The TUI client and daemon communicate over local TCP using a Redis-inspired protocol (RESP-style). The connection is bidirectional — the daemon can push events to the client without polling.

**Client → Daemon commands:**

| Command | Arguments | Description |
|---|---|---|
| `DISPATCH` | `<workflow-id> <payload>` | Start a workflow or task |
| `STATUS` | `<task-id>` | Query task state |
| `SUBSCRIBE` | `<task-id>` | Stream task events (push mode) |
| `CONTEXT` | `<query>` | Semantic search the context store |
| `AGENTS` | — | List running agent processes |
| `CANCEL` | `<task-id>` | Signal supervisor to stop a task |

**Daemon → Client push events (subscribe mode):**

- `AGENT_STARTED <agent-id> <role>`
- `AGENT_MESSAGE <agent-id> <text>`
- `TASK_COMPLETE <task-id>`
- `TASK_FAILED <task-id> <reason>`
- `CLARIFICATION_NEEDED <question>`

---

## Agent Team

### Roles

Each agent role is defined as a markdown file with YAML frontmatter. Roles live in a project-local `/roles` directory, with defaults bundled in the binary and surfaced via the setup wizard.

**Role file schema:**

```markdown
---
name: implementer
model: ollama/qwen2.5-coder
tools: [read_file, write_file, search_context, git_status]
can_spawn: []
can_delegate_to: [code-reviewer]
max_concurrent_tasks: 2
---

You are a software implementer. You receive precisely scoped tasks
with full context. Your job is to execute them cleanly...
```

### Defined Roles (v1 — Software Development Default)

| Role | Model tier | Responsibilities |
|---|---|---|
| **User Manager** | Frontier | Receives human input, resolves ambiguity, routes to PM, proxies clarification requests back to human |
| **Project Manager** | Frontier | Decomposes tasks into subtasks, searches context store before planning, assigns roles, monitors completion |
| **Implementer** | Local | Executes well-scoped coding tasks |
| **Code Reviewer** | Local | Reviews implementations against defined criteria |
| **Designer** | Local | UI/UX and asset tasks |

All human communication flows exclusively through the User Manager. The Project Manager never addresses the user directly.

Other domain configurations (content, marketing, research) are expressed purely through different role definition files. The orchestration layer is identical.

### Model Cost Tiering

```
Frontier (Claude Sonnet): User Manager, Project Manager
Local (Ollama):           Implementer, Code Reviewer, Designer
```

Frontier models handle low-frequency, high-ambiguity reasoning. Local models handle high-frequency, narrow-scope execution on context-rich tasks.

---

## Context Store

### Purpose

The context store is the system's shared memory. It enables agents to build on each other's work, provides recovery state after crashes, and is the mechanism by which local models receive the context they need to perform well.

### Architecture

- **SQLite** for structured storage and metadata filtering
- **sqlite-vec** extension for vector similarity search
- **Local embedding model** via Ollama (e.g. `nomic-embed-text`) for generating embeddings
- Owned by a single long-lived `GenServer` process; all reads/writes serialized through it; embedding calls dispatched to a worker pool

### Scoping

- **Per-project store:** each project maintains its own isolated SQLite file
- **Global layer:** a second store holds cross-project knowledge (reusable patterns, learned preferences, shared skills)
- Queries search the project store first, optionally including global results

### Entry Schema

```elixir
%ContextEntry{
  id: uuid,
  project_id: string,
  task_id: string | nil,
  agent_id: string,
  role: atom,
  type: :observation | :decision | :blocker | :tool_result | :plan,
  text: string,
  embedding: vector,
  timestamp: datetime,
  metadata: map
}
```

### Discovery Pattern

When an agent receives a task, before its first LLM call the orchestrator automatically:

1. Embeds the task description
2. Runs nearest-neighbor search scoped to the current project
3. Injects top-N results into the agent's system prompt as "relevant prior context"

Agents begin execution pre-loaded with accumulated institutional knowledge.

---

## Workflow System

Workflows are markdown files defining multi-agent pipelines. They live in `/workflows`.

**Example:**

```markdown
---
name: feature-implementation
---

1. project-manager: analyze requirements, produce task breakdown
2. implementer: execute each subtask from breakdown
3. code-reviewer: review each implementation
4. project-manager: integrate feedback, mark complete
```

The daemon dispatches workflows, not just tasks. Agent handoffs occur via the context store — agents write structured outputs and the workflow executor reads them to decide what to spawn next. This means any step is resumable after a crash.

---

## Skills System

Skills are reusable named sequences of tool calls and reasoning steps, defined as markdown files in `/skills`.

**Example:**

```markdown
---
name: security-review
tools: [read_file, search_context]
---

Review the provided code for: injection vulnerabilities, auth bypass,
insecure defaults, secrets in code...
```

Skills are indexed in the context store. The Project Manager discovers and assigns skills semantically — "I need a security check, there's a `security-review` skill, I'll assign it" — without hardcoded skill registration.

---

## MCP Integration

The daemon acts as an MCP client. MCP server processes are supervised by OTP — crashes are handled, connections are restarted. Each agent process invokes tools through a supervised MCP connection pool.

### MCP Servers (v1)

| Server | Purpose |
|---|---|
| Filesystem | Read/write project files |
| Git | Status, diff, commit, branch |
| Web Search | Research and documentation lookup |

Additional MCP servers can be configured per-project. The ecosystem is open — any compliant MCP server is immediately available to agents.

---

## CLI & TUI

### Distribution

Packaged via **Burrito** as a single self-contained binary per platform:

- `ant-linux-amd64`
- `ant-darwin-arm64`
- `ant-windows-amd64.exe`

Distributed via GitHub Releases with a curl install script. No Erlang/Elixir installation required.

### TUI Layout

Rich terminal UI with multiple panes:

```
┌─ Anthill ──────────────────────────────────────┐
│ Project: my-app          Agents: 3 active       │
├─ Task Feed ──────────────┬─ Agent Activity ─────┤
│ ✓ #41 Parse auth spec    │ implementer-1         │
│ ● #42 Write validate_    │ > Reading auth.ex...  │
│   token/1                │ > Writing changes...  │
│ ○ #43 Write tests        │                       │
│                          │ code-reviewer-1       │
│                          │ > Reviewing #41...    │
├─ Context ────────────────┴───────────────────────┤
│ > _                                              │
└──────────────────────────────────────────────────┘
```

### First-Run Setup Wizard

On first run in a new project directory, the wizard:

1. Detects the project type (language, framework)
2. Configures LLM providers (Ollama endpoint, Anthropic API key)
3. Selects and optionally customizes default role definitions
4. Initializes the context store
5. Configures MCP servers

---

## LLM Provider Support (v1)

| Provider | Usage |
|---|---|
| **Ollama** | Local models for execution-tier agents; embedding model |
| **Anthropic (Claude)** | Frontier models for User Manager and Project Manager |

Provider is configured per-role in the role frontmatter. Switching a role between providers requires only a config change.

---

## Filesystem & Remote Access

The daemon is co-located with the codebase — on the same machine or a remote server/VPS. All file reading and writing is performed directly by the daemon via MCP filesystem tools. The client is purely a UI with no file system access of its own.

This architecture has an important consequence: **the client can be anything, anywhere.** The daemon is the product. Clients are interchangeable thin interfaces over TCP.

### Client Targets

| Client | Notes |
|---|---|
| **TUI (v1)** | Rich terminal UI, runs locally or over SSH |
| **Mobile app** | iOS/Android thin client; describe tasks, stream progress, review diffs |
| **Web UI** | Browser-based frontend to the same TCP protocol |
| **Editor plugin** | LSP-adjacent integration for VS Code, Neovim, etc. |

The mobile client is a first-class target, not an afterthought. Developers increasingly want to initiate and monitor work away from a keyboard — reviewing agent progress, approving tasks, unblocking clarification requests from a phone. The User Manager's clarification loop is particularly well-suited to async mobile interaction.

### Deployment Models

**Local:** Daemon runs on the developer's machine alongside the codebase. TUI client connects over loopback.

**Remote:** Daemon runs on a VPS or home server with the codebase checked out. Any client connects over the network. The developer's machine is optional.

---

## Project Directory Structure

```
my-project/
  .anthill/
    config.toml          ← provider keys, MCP config
    context.db           ← per-project SQLite context store
    roles/               ← role markdown files (override defaults)
    workflows/           ← workflow definitions
    skills/              ← skill definitions
```

---

## MVP Scope

The v1 deliverable is the infrastructure layer:

- [ ] Elixir daemon with TCP listener (Thousand Island)
- [ ] RESP-style protocol implementation
- [ ] OTP supervision tree for agent processes
- [ ] Context store GenServer with SQLite + sqlite-vec
- [ ] Embedding via Ollama (`nomic-embed-text`)
- [ ] Semantic search with metadata filtering
- [ ] Discovery prompt injection on task start
- [ ] Role loading from markdown files
- [ ] MCP client pool (Filesystem, Git, Web Search)
- [ ] Single-agent execution (no multi-agent orchestration yet)
- [ ] Rich TUI with task feed and agent activity panes
- [ ] First-run setup wizard
- [ ] Burrito packaging → single binary per platform

**Explicitly out of scope for MVP:**
- Multi-agent workflows (User Manager → PM → team)
- Workflow definition files
- Global context store layer
- Skills system
- Remote daemon support

---

## Future Directions

- Full agent team with User Manager / Project Manager hierarchy
- Workflow DAG executor with dependency tracking
- Global context store with cross-project knowledge
- Skills discovery and assignment via semantic search
- Domain configuration packs (content/marketing, research, communications)
- **Mobile client** (iOS/Android) — task dispatch, progress streaming, clarification responses
- Web UI as alternative frontend
- Editor plugin (LSP-adjacent)
- Hot code reloading for agent role updates mid-task

---

## Open Questions

- **Embedding model:** `nomic-embed-text` vs `all-MiniLM` — benchmark on target hardware (RTX 2070/2080).
- **TUI library:** Ratatouille (Elixir Ratatui port) vs Owl — evaluate maturity.
- **Chunking strategy:** Define chunking rules for long agent outputs before context store write.
- **Mobile protocol:** Determine if raw TCP/RESP is suitable for mobile clients or if a WebSocket wrapper is preferable.
