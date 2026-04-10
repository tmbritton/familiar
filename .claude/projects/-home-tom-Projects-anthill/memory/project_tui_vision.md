---
name: project_tui_vision
description: Terminal UI vision — Ratatouille-based split-pane interface with streaming responses, tool visibility, and agent status
type: project
---

Epic 8 (was Web UI) should be preceded by a Terminal UI epic using Ratatouille.

**Vision:** Split-pane terminal interface like LazyGit:
- Chat pane: scrollable conversation with streaming token-by-token responses
- Tools pane: live display of tool calls and results as they happen
- Agents pane: active agents, status, tool call counts
- Input pane: user input with command history

**Key dependencies:**
- `stream_chat/2` implementation in OpenAICompatibleAdapter (currently stubbed)
- PubSub subscription for Activity events (already broadcasts :tool_call, :agent_complete)
- Ratatouille library for terminal rendering

**Why before Web UI:** The TUI solves the immediate UX gaps (streaming, tool visibility) without requiring Phoenix LiveView. It's the primary interface for CLI-first users. The Web UI (Epic 8) becomes optional/supplementary.
