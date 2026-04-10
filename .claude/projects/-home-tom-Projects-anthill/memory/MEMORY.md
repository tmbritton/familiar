# Memory Index

- [project_librarian_agent.md](project_librarian_agent.md) — Librarian GenServer for curated, multi-hop knowledge retrieval. Discovered in Epic 2 retro, woven into Epic 3 Story 3-1.
- [project_post_mvp_tools.md](project_post_mvp_tools.md) — Post-MVP tools: http_request (Req), fetch_page (Req+Floki), LSP integration. None block MVP.
- [project_cwd_audit.md](project_cwd_audit.md) — File.cwd!() audit: multiple modules default to Familiar source dir instead of project dir in CLI mode. Tracked for systematic fix.
- [project_tui_vision.md](project_tui_vision.md) — Terminal UI vision: Ratatouille split-pane with streaming, tool visibility, agent status. Epic 8, before Web UI.
- [project_embedding_reindex.md](project_embedding_reindex.md) — Switching embedding models requires re-indexing all vectors. Story 7.5-7 must handle model change detection.
- [project_web_ui_vision.md](project_web_ui_vision.md) — Long-term: multi-user agentic platform. Server-hosted, public web UI, concurrent users, real-time agent node graph.
- [project_distributed_vision.md](project_distributed_vision.md) — Far future: multi-instance Familiar via Erlang distribution. Cross-project agents, federated knowledge, distributed workflows.
- [project_mcp_support.md](project_mcp_support.md) — MCP support: Familiar as server (expose tools to editors) and client (use external MCP servers). Epic 9, before Web UI.
- [feedback_time_di.md](feedback_time_di.md) — When tests depend on wall clock time, inject the Clock behaviour. Don't use far-future dates or sleep.
- [feedback_flaky_tests_zero_tolerance.md](feedback_flaky_tests_zero_tolerance.md) — Zero tolerance for flaky tests: root-cause, stress-test 50x, never retry/skip/sleep. Lists 5 common flake patterns observed in this codebase.
