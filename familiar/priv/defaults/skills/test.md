---
name: test
description: Write and run tests for new or modified functionality
tools:
  - read_file
  - write_file
  - run_command
---
Write tests that verify the behavior described in the task requirements.

- Read existing test files to match the project's testing patterns and conventions
- Write descriptive test names that document expected behavior
- Cover the happy path, error cases, and edge cases
- Run the test suite after writing tests to confirm they pass
- If tests fail, diagnose the failure and fix either the test or the implementation
