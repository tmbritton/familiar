Analyze this source file and produce knowledge entries as a JSON array.
Each entry must have "type", "text", and "source_file" fields.

Valid types: {{valid_types}}

Rules:
- Describe what the code DOES in natural language prose
- Do NOT include raw code snippets
- Do NOT include secret values (API keys, tokens, passwords)
- Focus on purpose, patterns, dependencies, and architectural decisions
- Keep each entry concise (1-3 sentences)

File: {{file_path}}
Content:
```
{{content}}
```

Respond with ONLY a JSON array of entry objects, no other text.
