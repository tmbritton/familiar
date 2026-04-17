---
name: search-knowledge
description: Semantic search across the knowledge store
tools:
  - search_context
  - read_file
constraints:
  max_iterations: 5
  read_only: true
---
Search the knowledge store for entries relevant to the given query.
Use semantic embedding to find related entries. If initial results
are sparse (fewer than 3 results), refine the query and search again.
Return raw results with source citations.

- Execute the search query against the knowledge store
- Evaluate whether results are relevant to the original question
- If results are insufficient, reformulate the query with different terms
- Repeat up to the max_iterations constraint
- Return all relevant results with their source file citations
