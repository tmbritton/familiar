---
name: monitor-workers
description: Track running worker agent status and detect failures
tools:
  - monitor_agents
  - broadcast_status
---
Monitor running worker agents and report on their status.

- Query agent status periodically to detect completions and failures
- Broadcast status updates to keep the user and other agents informed
- Detect stuck or unresponsive agents based on activity timeouts
- Report worker completion with summary of changes made
- Flag any workers that exited with errors for failure evaluation
