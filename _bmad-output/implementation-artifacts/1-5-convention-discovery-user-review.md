# Story 1.5: Convention Discovery & User Review

Status: done

## Story

As a user,
I want Familiar to discover my project's conventions and show me the evidence,
So that I can verify the system understands my patterns and correct any misclassifications.

## Acceptance Criteria

1. **Given** the init scan has indexed project files, **When** convention discovery runs, **Then** the system identifies naming patterns, package structure, error handling, template patterns, and other conventions. Each convention includes evidence counts (e.g., "snake_case files (61/64 files)") per FR7d. Conventions are stored as knowledge entries of type "convention".

2. **Given** conventions are discovered, **When** the user is prompted to review, **Then** discovered conventions are displayed with evidence. The user can accept all, edit individual conventions, or correct misclassifications (FR5).

3. **Given** the project has language-specific commands, **When** validation runs during init, **Then** configured test, build, and lint commands are validated (FR6). Commands that fail produce clear error messages with instructions to fix.

4. **Given** convention discovery completes, **When** unit tests run, **Then** convention extraction logic is covered with test cases for multiple project structures. Evidence counting is verified to be accurate.

## Tasks / Subtasks

- [x] Task 1: Convention discoverer module with pattern analysis (AC: 1)
  - [x] 1.1 Create `Familiar.Knowledge.ConventionDiscoverer` with `discover/2` entry point
  - [x] 1.2 Implement structural pattern analysis: file naming, directory structure, module organization
  - [x] 1.3 Implement LLM-assisted convention analysis: prompt LLM with file list + sample content to identify cross-cutting conventions
  - [x] 1.4 Implement evidence counting: each convention includes count and total (e.g., 61/64 files)
  - [x] 1.5 Store conventions as knowledge entries with evidence in metadata JSON
  - [x] 1.6 Unit tests with mocked LLM and varied project structures

- [x] Task 2: Convention review CLI command (AC: 2)
  - [x] 2.1 Add `fam conventions` command to CLI Main (lists discovered conventions)
  - [x] 2.2 Implement convention display with evidence counts in text/json/quiet modes
  - [x] 2.3 Add `fam conventions review` subcommand (returns review_mode flag)
  - [x] 2.4 Convention query from knowledge store with metadata parsing
  - [x] 2.5 Text formatter with evidence counts and reviewed status
  - [x] 2.6 Unit tests for CLI command dispatch and output formatting

- [x] Task 3: Language command validation (AC: 3)
  - [x] 3.1 Create `Familiar.Knowledge.CommandValidator` using Shell behaviour port
  - [x] 3.2 Auto-detect language-specific commands from project structure (6 languages)
  - [x] 3.3 Validate detected commands via Shell behaviour
  - [x] 3.4 Return `{:ok, %{language, commands, failures}}` with detailed failure info
  - [x] 3.5 Unit tests with mocked Shell behaviour (12 tests)

- [x] Task 4: Integration with init pipeline (AC: 1, 2)
  - [x] 4.1 Wire convention discovery into InitScanner.run after extraction completes
  - [x] 4.2 Wire command validation into init pipeline
  - [x] 4.3 Display convention summary during init progress reporting
  - [x] 4.4 Convention count shown in init completion summary
  - [x] 4.5 Updated init scanner tests for full pipeline with conventions

### Review Findings

- [x] [Review][Decision] D1: No interactive accept/edit/reject flow for convention review — AC2 requires user can accept all, edit, or correct. Current implementation only lists conventions. Options: (a) implement CLI interactive prompts now, (b) defer interactive review to web UI in Epic 7
- [x] [Review][Patch] P1: CommandValidator accepts any exit code as success — should check `exit_code: 0` [command_validator.ex:110]
- [x] [Review][Patch] P2: CommandValidator runs real build commands (`cargo build`, `go build`) — should use safe probes only [command_validator.ex:56-67]
- [x] [Review][Patch] P3: `Jason.decode!` crashes on corrupted metadata — use `Jason.decode/1` with fallback [main.ex:195]
- [x] [Review][Patch] P4: Binary file content in LLM prompt — add `String.valid?/1` check [convention_discoverer.ex:235]
- [x] [Review][Patch] P5: Removed assertion for extraction_warnings in init scanner test [init_scanner_test.exs]
- [x] [Review][Patch] P6: `import Ecto.Query` inside function body — move to module level or use fully qualified [main.ex:185]
- [x] [Review][Defer] W1: Duplicate language indicator definitions across ConventionDiscoverer and CommandValidator — deferred, minor DRY concern
- [x] [Review][Defer] W2: `fam conventions` queries DB directly bypassing daemon HTTP — deferred, pragmatic for MVP

## Dev Notes

### Architecture Compliance

**Convention discovery is a post-extraction analysis step.** Story 1.4's Extractor already produces per-file convention entries via LLM. Story 1.5 adds a higher-level analysis that identifies cross-cutting patterns across ALL scanned files with statistical evidence. These are complementary: per-file extraction finds "this file uses snake_case", convention discovery aggregates to "snake_case files (61/64 files)".

**Module location:** `lib/familiar/knowledge/convention_discoverer.ex` — under the `knowledge/` context since conventions are knowledge entries.

**Convention entries with evidence:** Use the existing `metadata` field (JSON string) on `Knowledge.Entry` to store evidence:
```json
{"evidence_count": 61, "evidence_total": 64, "evidence_ratio": 0.95, "reviewed": false}
```

**Knowledge-not-code rule applies:** Conventions are prose descriptions with evidence, not code patterns. Example: "Module files use snake_case naming (61/64 files)" not "defmodule FooBar → foo_bar.ex".

**CLI interaction for review:** Convention review is a CLI command (`fam conventions review`), not a web UI. The init pipeline runs in-process without the Phoenix endpoint, so web review is not available during first init. Post-init review via web UI is deferred to Epic 7.

**Shell behaviour for command validation:** Use `Familiar.System.Shell` for running validation commands. This is already mockable via `ShellMock`. The production adapter `RealShell` needs to be created (similar to how `LocalFileSystem` was created in 1.4).

### Existing Infrastructure to Reuse

| What | Where | How to use |
|------|-------|------------|
| Knowledge entry schema | `Familiar.Knowledge.Entry` | Has `convention` type and `metadata` field for evidence |
| Store with embedding | `Familiar.Knowledge.store_with_embedding/1` | Store discovered conventions with embeddings |
| Init scanner pipeline | `Familiar.Knowledge.InitScanner` | Wire convention discovery after extraction step |
| LLM behaviour | `Familiar.Providers.LLM` | Use for cross-cutting convention analysis |
| Shell behaviour | `Familiar.System.Shell` | Use for command validation |
| CLI Main | `Familiar.CLI.Main` | Add `conventions` command |
| Output formatting | `Familiar.CLI.Output` | Format convention display in json/text/quiet modes |
| FileSystem behaviour | `Familiar.System.FileSystem` | Read project files for structural analysis |
| LocalFileSystem adapter | `Familiar.System.LocalFileSystem` | Production file reading |
| Extractor | `Familiar.Knowledge.Extractor` | Per-file conventions already extracted; discoverer aggregates |
| Mox mocks | `test/support/mocks.ex` | LLMMock, ShellMock, FileSystemMock |

**Do NOT create:**
- New Ecto schemas — `Knowledge.Entry` with metadata covers convention evidence
- New database tables — `knowledge_entries` suffices
- New behaviours — use existing Shell and LLM ports
- Web UI for review — deferred to Epic 7

### Convention Discovery Strategy

**Two-phase approach:**

**Phase 1 — Structural analysis (no LLM needed):**
- File naming patterns: count extensions, case styles (snake_case, camelCase, kebab-case)
- Directory structure: identify common directories (lib/, test/, src/, etc.) and their roles
- Config file presence: detect language/framework from mix.exs, package.json, Cargo.toml, etc.
- Test organization: test/ mirrors lib/, test filenames end in _test.exs, etc.

**Phase 2 — LLM-assisted cross-cutting analysis:**
- Send file list + sample content from representative files to LLM
- Prompt for: error handling patterns, module organization, naming conventions, architecture patterns
- Parse structured JSON response into convention entries with evidence

### Language Command Detection

Auto-detect based on project files present:

| Indicator File | Language | Test Command | Build Command | Lint Command |
|---|---|---|---|---|
| `mix.exs` | Elixir | `mix test` | `mix compile` | `mix credo --strict` |
| `package.json` | Node.js | `npm test` | `npm run build` | `npm run lint` |
| `go.mod` | Go | `go test ./...` | `go build ./...` | `golangci-lint run` |
| `Cargo.toml` | Rust | `cargo test` | `cargo build` | `cargo clippy` |
| `pyproject.toml` | Python | `pytest` | — | `ruff check .` |
| `Gemfile` | Ruby | `bundle exec rspec` | — | `bundle exec rubocop` |

Validation: run each detected command with a safe flag (e.g., `--help` or `--dry-run`) to verify it's installed and configured. Don't actually run tests during init.

### RealShell Production Adapter

Create `lib/familiar/system/real_shell.ex` implementing `Familiar.System.Shell` behaviour:
```elixir
def cmd(command, args, opts) do
  case System.cmd(command, args, opts ++ [stderr_to_stdout: true]) do
    {output, 0} -> {:ok, %{output: output, exit_code: 0}}
    {output, code} -> {:ok, %{output: output, exit_code: code}}
  end
rescue
  e -> {:error, {:shell_error, %{reason: Exception.message(e)}}}
end
```

Register in `config/config.exs`: `config :familiar, Familiar.System.Shell, Familiar.System.RealShell`

### Testing Strategy

**ConventionDiscoverer tests:**
- Mock LLM for cross-cutting analysis responses
- Use `@moduletag :tmp_dir` with varied project structures (Elixir, mixed, empty)
- Verify evidence counts are accurate
- Test with inconsistent naming (some snake_case, some camelCase) to verify ratio

**CLI conventions tests:**
- Mock convention data in knowledge store
- Test display formatting in all three modes
- Test interactive review flow (accept/edit/reject)
- Function injection for deps like previous stories

**CommandValidator tests:**
- Mock Shell behaviour for command execution
- Test each language detection case
- Test validation failure reporting

**Integration tests:**
- Full pipeline: scan → extract → discover → validate → review
- Use Ecto sandbox for real DB, mock LLM/Shell/FileSystem

### Previous Story Learnings

From story 1.4:
- **FileSystem behaviour port** must be used for file operations (D2 fix from code review)
- **Signal trapping** via `System.trap_signal/2` for cleanup on interrupt
- **`Task.async_stream`** with `on_timeout: :kill_task` and handling `{:exit, _}` tuples
- **`:counters` module** — `add/3` returns `:ok`, use separate `get/2` call
- **Credo strict** — extract nested logic into separate functions, avoid deep nesting
- **Evidence in metadata** — store as JSON string in Entry.metadata field
- **LocalFileSystem adapter** created in 1.4 — reuse pattern for RealShell

### Init Pipeline Integration Flow

```
fam init (existing from 1.4)
  ├─ 1-6. [existing] scan → classify → extract → embed → store → install defaults
  ├─ 7. [NEW] Convention discovery
  │     ├─ Structural analysis (file patterns, directory structure)
  │     └─ LLM cross-cutting analysis (error handling, architecture patterns)
  ├─ 8. [NEW] Language command validation
  │     ├─ Detect language from project files
  │     └─ Validate test/build/lint commands via Shell
  ├─ 9. [NEW] Display convention summary
  │     └─ Show discovered conventions with evidence counts
  └─ 10. [MODIFIED] Completion summary includes convention count

Post-init:
  fam conventions          — list all discovered conventions
  fam conventions review   — interactive accept/edit/reject flow
```

### Project Structure Notes

New files to create:
```
lib/familiar/knowledge/
  └── convention_discoverer.ex    # Cross-cutting convention analysis
lib/familiar/knowledge/
  └── command_validator.ex        # Language command detection and validation
lib/familiar/system/
  └── real_shell.ex               # Production Shell adapter

test/familiar/knowledge/
  ├── convention_discoverer_test.exs
  └── command_validator_test.exs
test/familiar/system/
  └── real_shell_test.exs
```

Modify:
- `lib/familiar/knowledge/init_scanner.ex` — wire convention discovery and command validation
- `lib/familiar/cli/main.ex` — add `conventions` and `conventions review` commands
- `lib/familiar/cli/output.ex` — add convention-specific error messages
- `config/config.exs` — register RealShell adapter

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 1, Story 1.5]
- [Source: _bmad-output/planning-artifacts/architecture.md — Convention injection MVP strategy, Init scan architecture, Knowledge entry content strategy, Shell behaviour]
- [Source: _bmad-output/implementation-artifacts/1-4-project-initialization-file-scanning.md — Init pipeline, FileSystem port usage, testing patterns]
- [Source: lib/familiar/knowledge/entry.ex — Entry schema with convention type and metadata field]
- [Source: lib/familiar/knowledge/init_scanner.ex — Init pipeline orchestration]
- [Source: lib/familiar/system/shell.ex — Shell behaviour definition]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Created ConventionDiscoverer with two-phase approach: structural analysis (no LLM) + LLM cross-cutting analysis
- Structural analysis detects: file naming patterns (snake_case), directory structure, language/framework, extension distribution
- LLM analysis prompts for: error handling, module organization, naming conventions, architecture patterns
- Evidence counting stored in metadata JSON: `{"evidence_count": N, "evidence_total": M, "evidence_ratio": 0.95, "reviewed": false}`
- Created CommandValidator: auto-detects 6 languages from indicator files, validates test/build/lint commands via Shell behaviour
- Created RealShell production adapter for Shell behaviour
- CLI: added `fam conventions` and `fam conventions review` commands with text/json/quiet formatting
- Init pipeline extended: scan → extract → discover conventions → validate commands → embed → store
- Convention count shown in init completion summary
- 26 new tests (291 total + 4 properties), 0 failures
- Credo strict: 0 issues

### File List

New files:
- lib/familiar/knowledge/convention_discoverer.ex
- lib/familiar/knowledge/command_validator.ex
- lib/familiar/system/real_shell.ex
- test/familiar/knowledge/convention_discoverer_test.exs
- test/familiar/knowledge/command_validator_test.exs
- test/familiar/cli/conventions_command_test.exs

Modified files:
- lib/familiar/knowledge/init_scanner.ex (wired convention discovery + command validation)
- lib/familiar/cli/main.ex (added conventions command, updated init text formatter)
- lib/familiar/cli/output.ex (convention error messages — no changes needed, existing catch-all works)
- config/config.exs (registered RealShell adapter)
- test/familiar/knowledge/init_scanner_test.exs (updated for convention discovery in pipeline)
