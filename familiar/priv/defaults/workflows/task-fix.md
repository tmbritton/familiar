---
name: task-fix
description: Fix a bug or address a failing task
steps:
  - name: diagnose
    role: analyst
  - name: fix
    role: coder
    input:
      - diagnose
  - name: verify
    role: coder
    input:
      - fix
---
# Task Fix Workflow

Guide the agent through fixing a bug or addressing a failing task.

1. **diagnose** — Understand the issue, research relevant code and recent changes, identify root cause
2. **fix** — Using the diagnosis, implement the fix following project conventions and write regression tests
3. **verify** — Run the test suite, validate the fix resolves the issue without regressions
