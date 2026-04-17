---
name: feature-planning
description: Plan a new feature from description to approved specification
steps:
  - name: research
    role: analyst
  - name: draft-spec
    role: analyst
    mode: interactive
    input:
      - research
  - name: review-spec
    role: reviewer
    input:
      - draft-spec
---
# Feature Planning Workflow

Guide the agent through planning a new feature from requirements to specification.

1. **research** — Search the knowledge store and codebase for relevant context, conventions, and prior decisions
2. **draft-spec** — Using research context, draft a specification with acceptance criteria, affected files, and trade-offs
3. **review-spec** — Review the drafted specification for completeness, feasibility, and alignment with conventions
