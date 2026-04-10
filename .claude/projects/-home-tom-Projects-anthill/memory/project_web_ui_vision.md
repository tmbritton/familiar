---
name: project_web_ui_vision
description: Long-term vision for Web UI — multi-user agentic programming platform with server-hosted Familiar instance
type: project
---

**Vision:** Multi-user agentic programming platform.

**Architecture:**
- Familiar instance lives on a server alongside the project files
- Web UI is publicly exposed to the internet
- Multiple users log in simultaneously
- Each user has their own chat sessions, can run workflows, use all CLI capabilities
- Agents execute against the shared codebase with file-level claim checking (already built in Story 5.5-2) preventing concurrent write conflicts

**Key implications for architecture:**
- **Authentication & authorization** — user accounts, sessions, permissions (who can write vs read-only)
- **Session isolation** — each user's conversations, agent processes, and tool calls are scoped to their user
- **Concurrent agent safety** — multiple users' agents may write files simultaneously. File claim checking (already implemented) prevents conflicts, but UI needs to surface claims/conflicts clearly
- **Real-time updates** — LiveView + PubSub (already in place) for live agent status, tool calls, streaming responses across all connected users
- **Shared knowledge store** — all users benefit from the same project knowledge base
- **Activity feed** — who is doing what, which agents are running, what files are being modified

**Node graph visualization:**
- Real-time node graph of all agents and tool calls in the system
- Agents are nodes, tool calls and spawn_agent are edges
- Pulsing/active state when running, greyed when complete
- Click node → see conversation. Click edge → see tool call args/result
- Data source: Activity PubSub events (already broadcasting agent_started, tool_call, agent_complete)
- Web UI: D3.js force-directed graph updated via LiveView WebSocket
- TUI: simplified tree view in agents pane (text-based pstree style)

**Why this matters:** Familiar already has the right foundation:
- Phoenix/LiveView for real-time web
- PubSub for event broadcasting
- Conversation persistence in SQLite (scoped by user in future)
- File transaction module with claim checking
- Agent supervision under DynamicSupervisor
- Extension system for adding capabilities

**Epic 9 (Web UI) should be planned with this multi-user vision from the start**, even if v1 is single-user. Schema decisions (user_id on conversations, sessions, file claims) are cheaper to make early.
