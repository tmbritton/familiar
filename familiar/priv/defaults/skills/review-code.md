---
name: review-code
description: Analyze code changes for correctness, style, and potential issues
tools:
  - read_file
  - list_files
  - search_files
  - search_context
---
Review code changes systematically for quality and correctness.

- Read the changed files and understand the intent of each modification
- Search the knowledge store for relevant conventions and patterns
- Check that error handling follows project standards
- Verify test coverage exists for new or changed behavior
- Look for common issues: missing nil checks, unhandled error cases, resource leaks
- Compare against established project patterns found in the knowledge store
