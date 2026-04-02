# Memory Index

- [project_rename_familiar.md](project_rename_familiar.md) — Project renamed from Anthill to Familiar during UX design. Tracks all PRD deltas requiring reconciliation.
- [feedback_testing.md](feedback_testing.md) — Extensive testing is critical for AI-agent-built code. Prefers hexagonal architecture and DI for testability.
- [project_cli_first.md](project_cli_first.md) — All capabilities via CLI with JSON output; web UI is optional. Enables third-party agent integration (e.g., Pi).
- [project_extensibility.md](project_extensibility.md) — Extensibility via behaviour ports now, runtime plugins post-MVP. Extensions must not bypass safety enforcement.
- [project_agents_as_actors.md](project_agents_as_actors.md) — Agent tasks are GenServers under DynamicSupervisor. Core reason BEAM/OTP was chosen.
- [project_librarian_agent.md](project_librarian_agent.md) — Librarian GenServer for curated, multi-hop knowledge retrieval. Discovered in Epic 2 retro, woven into Epic 3 Story 3-1.
- [feedback_time_di.md](feedback_time_di.md) — When tests depend on wall clock time, inject the Clock behaviour. Don't use far-future dates or sleep.
