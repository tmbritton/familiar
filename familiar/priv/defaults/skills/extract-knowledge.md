---
name: extract-knowledge
description: Extract knowledge entries from completed work artifacts
tools:
  - search_context
  - store_context
  - read_file
---
Extract institutional knowledge from completed task output.

- Read the task output, changed files, and any review feedback
- Identify conventions applied, decisions made, and relationships discovered
- Search the knowledge store for existing entries to avoid duplicates
- Store each new insight as a separate, focused knowledge entry
- Cite source files in each entry using "[file_path]" format
- Capture knowledge ABOUT the code, not the code itself
