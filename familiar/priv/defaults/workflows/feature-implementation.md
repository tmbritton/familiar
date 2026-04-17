---
name: feature-implementation
description: Implement an approved feature specification
steps:
  - name: implement
    role: coder
  - name: test
    role: coder
    input:
      - implement
  - name: review
    role: reviewer
    input:
      - implement
      - test
---
# Feature Implementation Workflow

Guide the agent through implementing an approved feature specification.

1. **implement** — Create or modify files following the specification and project conventions
2. **test** — Write tests for the implemented functionality, run the test suite to verify correctness
3. **review** — Review both implementation and test changes for correctness, conventions, and coverage
