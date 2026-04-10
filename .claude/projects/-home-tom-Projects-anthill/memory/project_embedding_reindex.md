---
name: project_embedding_reindex
description: Switching embedding models requires re-indexing all vectors. Story 7.5-7 must handle model change detection.
type: project
---

When the embedding model changes (e.g., switching from nomic-embed-text to text-embedding-3-small), all stored vectors become invalid — different models produce incompatible vector spaces.

**Requirements for Story 7.5-7:**
- Store the embedding model name in the database (metadata table or config)
- On startup, compare configured model vs stored model
- If different, warn user and suggest `fam context --reindex`
- `--reindex` reads all text entries, re-embeds with new model, replaces vectors
- Also needed when vector dimensions change (768 vs 1536) — would require recreating the sqlite-vec virtual table

**Why:** User asked about switching models. Mixing vectors from different models produces meaningless search results.

**Recommended model: `openai/text-embedding-3-small`** via OpenRouter
- $0.02/M tokens (cheapest option, 7.5x cheaper than Gemini)
- 1536 dimensions — requires migration from current 768
- Excellent quality for code/docs retrieval
- Standard OpenAI `/v1/embeddings` endpoint via OpenRouter

**Migration needed:** Change sqlite-vec virtual table from `float[768]` to `float[1536]`. No data in production DBs yet so this is a clean migration.

**Config:**
```toml
[providers.openrouter]
embedding_model = "openai/text-embedding-3-small"
```
