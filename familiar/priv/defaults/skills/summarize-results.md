---
name: summarize-results
description: Synthesize search results into concise context summaries
tools:
  - search_context
constraints:
  read_only: true
---
Summarize a set of search results into a concise, actionable context block.

- Group related information by topic
- Cite sources using "[source_file]" after each claim
- Prioritize specific facts over general descriptions
- Exclude results not relevant to the original query
- If results conflict, present both perspectives with sources
- Keep summaries focused and under 500 words unless more detail is needed
