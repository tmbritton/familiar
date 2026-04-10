---
name: project_mcp_support
description: MCP (Model Context Protocol) support — Familiar as both MCP server and MCP client for tool/resource interop
type: project
---

**MCP support has two sides:**

**1. Familiar as MCP Server** — expose Familiar's tools and knowledge store to external clients (Claude Code, Cursor, VS Code, etc.)
- External tools can call Familiar's agents, search its knowledge store, run workflows
- Familiar becomes a backend service that any MCP-aware editor/tool can connect to
- Maps cleanly: each Familiar tool (read_file, search_context, spawn_agent) becomes an MCP tool
- Knowledge store entries become MCP resources

**2. Familiar as MCP Client** — agents can call external MCP servers for additional capabilities
- An agent could use a GitHub MCP server to create PRs, read issues
- An agent could use a database MCP server to query production data
- Extension system already supports adding tools — MCP tools would register via the same ToolRegistry
- Each MCP server connection = a Familiar extension that registers its tools

**Implementation approach:**
- MCP uses JSON-RPC over stdio or HTTP/SSE
- Server mode: Phoenix endpoint handles MCP protocol, dispatches to ToolRegistry
- Client mode: GenServer per MCP connection, registers discovered tools in ToolRegistry
- The Extension behaviour could be extended to support MCP server discovery

**Priority:** After TUI (Epic 8), before or alongside Web UI (Epic 9). MCP server mode is particularly valuable — it lets Familiar work as a backend for any editor.
