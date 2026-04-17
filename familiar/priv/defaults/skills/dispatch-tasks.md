---
name: dispatch-tasks
description: Spawn and coordinate worker agents for task execution
tools:
  - spawn_agent
  - broadcast_status
  - read_file
  - write_file
  - list_files
---
Dispatch tasks to worker agents respecting dependency ordering.

- Read task files from .familiar/tasks/ to determine dependencies and status
- Only dispatch tasks whose dependencies are complete
- Track intended files per worker to prevent conflicts
- Update task file status as workers complete
- Respect the configured concurrency limit for parallel execution
- Broadcast status updates as tasks are dispatched and completed
