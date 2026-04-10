---
name: project_distributed_vision
description: Long-term vision for distributed Familiar — multi-instance agents communicating across codebases via Erlang distribution
type: project
---

**Vision:** Multiple Familiar instances on different servers, each managing a different codebase, with agents that can communicate across instances transparently via Erlang distribution.

**Capabilities enabled:**
- Cross-project agent queries (ask another project's librarian about its API)
- Distributed workflows (plan features spanning multiple repos)
- Cross-instance agent spawning (PM on coordinator spawns coders on microservice instances)
- Shared/federated knowledge across codebases
- Integration test coordination across projects

**Why BEAM makes this natural:**
- `GenServer.call({name, :"familiar@other-server"}, msg)` — one line for cross-node RPC
- PubSub with PG2 for cross-node event broadcasting
- Tool registry could register "remote" tools that dispatch via :rpc
- Supervision trees work across nodes

**Future epic, well beyond MVP.** But the architecture should not prevent it — avoid assumptions that there's only one Familiar instance or one project.
