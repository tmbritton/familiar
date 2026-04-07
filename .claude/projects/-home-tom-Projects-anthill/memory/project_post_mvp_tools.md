---
name: post_mvp_tools
description: Post-MVP tool additions planned for the agent harness — web access, page fetching, LSP integration
type: project
---

Post-MVP tools to add to the Familiar agent harness tool registry:

1. **`http_request`** — Raw HTTP via `Req`. Fetch API docs, package registries, JSON endpoints. Single story, trivial effort.
2. **`fetch_page`** — `Req` + `Floki` for HTML fetch + text extraction. Gives agents readable web content without JS execution. Small effort.
3. **LSP integration** — Language-aware code intelligence (go-to-definition, find-references, type info). Requires LSP client in harness + per-language server. Separate epic, large effort. Elixir: `elixir-ls` or `next-ls`.

**Why:** Discussed in Epic 7 party mode (2026-04-06). Consensus: none block MVP. The harness + CLI + chat mode is the product; tools are plugins added via `ToolRegistry.register`.

**How to apply:** When planning post-MVP epics, include a "Web Tools" epic with stories for http_request and fetch_page, and an "LSP Integration" epic for code intelligence.
