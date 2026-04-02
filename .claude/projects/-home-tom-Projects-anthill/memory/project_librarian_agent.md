---
name: Librarian Agent Pattern
description: Architectural discovery from Epic 2 retro — GenServer mediating all knowledge queries with multi-hop retrieval and summarization. Woven into Epic 3 Story 3-1.
type: project
---

Librarian agent pattern identified during Epic 2 retrospective (2026-04-02). A GenServer that mediates all knowledge store queries for both agents and users.

**Why:** Raw `Knowledge.search/1` returns all ranked entries, consuming tokens in the querying agent's context. A librarian curates and summarizes, saving tokens and improving relevance. This was the original motivation for an external context store.

**How to apply:**
- Woven into Epic 3 Story 3-1 (Planning Conversation Engine), not a separate story
- Ephemeral GenServer under DynamicSupervisor — spins up per query, shuts down after delivering results
- NOT a long-running process. Fresh context for each query prevents stale state and keeps memory bounded
- Serves both agent and user queries
- `fam search` defaults to librarian-curated results; `--raw` flag for unfiltered
- Multi-hop: evaluate results → detect gaps → re-query with refined terms → synthesize (all within the single query lifecycle)
- Epic 3 Story 3-1 scope must be updated to incorporate this before story creation
