---
name: evaluate-failures
description: Assess worker failures and determine recovery strategy
tools:
  - read_file
  - search_context
  - broadcast_status
---
Evaluate worker agent failures and recommend recovery actions.

- Read the failure context: error messages, stack traces, partial output
- Search the knowledge store for similar past failures and their resolutions
- Classify the failure type: transient (retry), context-stale (refresh + retry), or permanent (escalate)
- For transient failures: recommend automatic retry (max 1 attempt)
- For permanent failures: prepare a clear escalation summary with your analysis
- Apply circuit breaker: if 3+ failures of the same type occur in a batch, stop retrying that type
