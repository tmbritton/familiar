# Story 1.6: Configuration & Auto-Init

Status: done

## Story

As a user,
I want project-local configuration in a simple TOML file and automatic initialization on first use,
So that setup is effortless and preferences persist across sessions.

## Acceptance Criteria

1. **Given** init has completed, **When** the user checks `.familiar/config.toml`, **Then** it contains default configuration for: provider settings, language config, scan preferences, notification preferences. Default language configurations exist for Go and Elixir.

2. **Given** a directory without `.familiar/`, **When** the user runs any `fam` command (not just `fam init`), **Then** initialization is triggered automatically (FR7c). After init completes, the original command is executed.

3. **Given** the user edits config.toml with invalid values, **When** the config is loaded, **Then** validation produces `{:error, {:invalid_config, %{field: ..., reason: ...}}}` with specific field and reason. The daemon does not crash — it reports the error and uses defaults where possible.

4. **Given** the `--json` flag is used on any CLI command, **When** the command executes, **Then** output follows the consistent JSON envelope: `{"data": ...}` for success, `{"error": {"type": "...", "message": "...", "details": {...}}}` for errors (FR78). `--quiet` mode outputs minimal text suitable for scripting.

5. **Given** configuration and auto-init are implemented, **When** unit tests run, **Then** TOML parsing, validation, and default generation are covered. Auto-init trigger logic is tested.

## Tasks / Subtasks

- [x] Task 1: Configuration module with TOML parsing and validation (AC: 1, 3)
  - [x] 1.1 Create `Familiar.Config` module with `load/1` and `defaults/0`
  - [x] 1.2 Define config schema: provider, language, scan, notification sections
  - [x] 1.3 Implement TOML parsing via `Toml.decode_file/1` with graceful error handling
  - [x] 1.4 Implement field-level validation returning `{:ok, config}` or `{:error, {:invalid_config, %{field: ..., reason: ...}}}`
  - [x] 1.5 Implement `merge_with_defaults/1` — invalid/missing fields fall back to defaults, valid fields override
  - [x] 1.6 Default language configs for Elixir and Go (test/build/lint commands, skip patterns, source extensions)
  - [x] 1.7 Unit tests: parsing valid TOML, invalid TOML, missing file (use defaults), partial config, field validation errors

- [x] Task 2: Config file generation during init (AC: 1)
  - [x] 2.1 Create `Familiar.Config.Generator` with `generate_default/2` (project_dir, detected_language)
  - [x] 2.2 Write `.familiar/config.toml` with commented defaults during init
  - [x] 2.3 Wire into InitScanner pipeline after DefaultFiles.install
  - [x] 2.4 Use CommandValidator's detected language to populate language section
  - [x] 2.5 Unit tests: config file generated with correct content, doesn't overwrite existing

- [x] Task 3: Config integration with daemon and CLI (AC: 2, 3)
  - [x] 3.1 Add `config_path/0` to `Familiar.Daemon.Paths` returning `.familiar/config.toml`
  - [x] 3.2 Load config at daemon startup — apply provider/ollama settings from TOML
  - [x] 3.3 Add `fam config` CLI command listing current config values
  - [x] 3.4 Add error message for `:invalid_config` in Output module
  - [x] 3.5 Unit tests: config loading, daemon startup with valid/invalid config

- [x] Task 4: Auto-init refinement and JSON output audit (AC: 2, 4)
  - [x] 4.1 Verify auto-init in main.ex works for all commands (already implemented — audit and test)
  - [x] 4.2 Audit JSON output envelope consistency across all commands — ensure `{"data": ...}` / `{"error": {...}}` contract
  - [x] 4.3 Verify `--quiet` mode works consistently across all commands
  - [x] 4.4 Integration tests: auto-init triggers from non-init commands, original command executes after init
  - [x] 4.5 Test JSON envelope for every command in success and error cases

### Review Findings

- [x] [Review][Decision] D1: Validation fails fast instead of using defaults for invalid fields — chose fail-fast (simpler, clear errors, user fixes one at a time)
- [x] [Review][Patch] P1: `String.to_atom/1` on user-controlled TOML keys — fixed, keep keys as strings [config.ex:120-127]
- [x] [Review][Patch] P2: Empty string `""` for provider fields silently replaced by defaults via `||` pattern — dismissed, empty string is truthy in Elixir
- [x] [Review][Defer] W1: `--quiet` mode outputs "ok" for all success commands — not command-specific for scripting. Deferred, pre-existing design across all commands
- [x] [Review][Defer] W2: `validate_language/1` performs no type validation on values — deferred, minor since language section values are only consumed by display code currently

## Dev Notes

### Architecture Compliance

**Configuration is data, not code** (architecture principle). The TOML file is the single source of truth for project-local settings. Adding new languages or changing defaults requires editing config.toml, not Elixir code.

**No global config.** All configuration is project-local in `.familiar/`. Same config needed across projects → copy the file. No `~/.familiar/` global directory.

**Config module location:** `lib/familiar/config.ex` — top-level context since config is cross-cutting, not owned by knowledge or CLI.

**Graceful degradation:** If config.toml is missing or invalid, the system MUST still work using hardcoded defaults. The daemon never crashes from bad config — it logs a warning and falls back.

### TOML Library

Already in deps: `{:toml, "~> 0.7"}` (Toml 0.7.0). API:

```elixir
# Parse a TOML file
Toml.decode_file("path/to/config.toml")
# => {:ok, %{"section" => %{"key" => "value"}}}
# => {:error, %Toml.Error{}}

# Parse a TOML string (useful for testing)
Toml.decode("key = \"value\"")
# => {:ok, %{"key" => "value"}}
```

Keys are returned as strings, not atoms. The config module must handle string keys from TOML and convert to the internal config struct.

### Default Config Template

```toml
# Familiar project configuration
# Edit this file to customize Familiar's behavior for this project.

[provider]
# Ollama connection settings
base_url = "http://localhost:11434"
chat_model = "llama3.2"
embedding_model = "nomic-embed-text"
timeout = 120

[language]
# Detected language: elixir (or go, nodejs, etc.)
# name = "elixir"
# test_command = "mix test"
# build_command = "mix compile"
# lint_command = "mix credo --strict"
# dep_file = "mix.exs"
# skip_patterns = ["_build/", "deps/", "cover/"]
# source_extensions = [".ex", ".exs"]

[scan]
# max_files = 200
# large_project_threshold = 500

[notifications]
# provider = "auto"  # auto-detect, terminal-notifier, notify-send, or none
# enabled = true
```

The generated config should have detected language values uncommented and filled in.

### Language Defaults

Two built-in language configurations (per PRD — MVP ships Go + Elixir):

```elixir
@language_defaults %{
  "elixir" => %{
    test_command: "mix test",
    build_command: "mix compile",
    lint_command: "mix credo --strict",
    dep_file: "mix.exs",
    skip_patterns: ["_build/", "deps/", "cover/"],
    source_extensions: [".ex", ".exs"]
  },
  "go" => %{
    test_command: "go test ./...",
    build_command: "go build ./...",
    lint_command: "golangci-lint run",
    dep_file: "go.mod",
    skip_patterns: ["vendor/"],
    source_extensions: [".go"]
  }
}
```

Other languages detected by CommandValidator (nodejs, rust, python, ruby) should still work — they just won't have pre-populated defaults in config.toml.

### Config Struct

Use a plain map or struct — NOT an Ecto schema. Config is a runtime value, not a database entity.

```elixir
defmodule Familiar.Config do
  defstruct [
    provider: %{base_url: "http://localhost:11434", chat_model: "llama3.2",
                embedding_model: "nomic-embed-text", timeout: 120},
    language: %{},  # populated from detection or config file
    scan: %{max_files: 200, large_project_threshold: 500},
    notifications: %{provider: "auto", enabled: true}
  ]
end
```

### Auto-Init (Already Partially Implemented)

The `run/2` catch-all clause in `main.ex:82-95` already triggers auto-init for any command when `.familiar/` doesn't exist. **Audit this — don't rewrite it.** Verify:
- It calls `run_init(deps)` first
- On success, retries the original command via `run_with_daemon/2`
- On failure, returns the error (no retry)

The auto-init flow is complete. This task is primarily about testing it thoroughly and ensuring config.toml is created during init.

### JSON Output Envelope (Already Implemented)

`Familiar.CLI.Output` already implements the JSON envelope contract:
- Success: `{"data": ...}` (output.ex:29-31)
- Error: `{"error": {"type": "...", "message": "...", "details": {...}}}` (output.ex:33-41)
- Quiet mode: "ok" / "error: type" (output.ex:61-67)

**Audit — don't rewrite.** Verify all commands produce correct JSON when `--json` is passed. The text formatters in main.ex must handle all result shapes. Look for commands that might return unexpected data shapes.

### Existing Infrastructure to Reuse

| What | Where | How to use |
|------|-------|------------|
| TOML library | `{:toml, "~> 0.7"}` in mix.exs | Parse config.toml via `Toml.decode_file/1` |
| Paths module | `Familiar.Daemon.Paths` | Add `config_path/0`, existing `familiar_dir/0` |
| DefaultFiles | `Familiar.Knowledge.DefaultFiles` | Pattern for installing files during init |
| InitScanner | `Familiar.Knowledge.InitScanner` | Wire config generation after DefaultFiles.install |
| Output module | `Familiar.CLI.Output` | Already has JSON envelope — add `:invalid_config` error message |
| Main.ex auto-init | `Familiar.CLI.Main:82-95` | Already implemented — audit and test |
| CommandValidator | `Familiar.Knowledge.CommandValidator` | Detected language feeds config generation |
| App config | `config/config.exs` | Current Ollama defaults to use as fallbacks |

**Do NOT create:**
- New Ecto schemas — config is a runtime struct, not a DB entity
- New behaviours — config loading is internal, no need for a port
- New CLI output modes — json/text/quiet already work
- Global config — all config is project-local per architecture

### Config Loading Flow

```
Daemon startup:
  1. Read .familiar/config.toml via Toml.decode_file/1
  2. If file missing → use defaults (no error)
  3. If file invalid → log warning, use defaults, return {:error, {:invalid_config, ...}}
  4. Merge parsed TOML with defaults (TOML values override defaults)
  5. Apply provider settings to Ollama adapter config
  6. Store config in Application env or pass through supervision tree

CLI `fam config`:
  1. Ensure daemon running
  2. Read config from daemon (or read file directly if daemon-less)
  3. Display in text/json/quiet format
```

### Testing Strategy

**Config module tests:**
- Parse valid TOML string → correct struct
- Parse TOML with missing sections → defaults filled in
- Parse TOML with invalid values → `{:error, {:invalid_config, ...}}` with field/reason
- Missing config file → defaults returned (no error)
- Partial config → merge with defaults correctly

**Config generator tests:**
- Generate default config → valid TOML content
- Generate with detected language → language section populated
- Don't overwrite existing config file

**Auto-init tests:**
- Any command in dir without `.familiar/` → init runs → command executes
- Init failure → error returned, original command not attempted
- Already initialized → command runs directly

**JSON envelope audit tests:**
- Every command with `--json` → output is valid JSON matching envelope contract
- Error cases → `{"error": {"type": ..., "message": ..., "details": ...}}`
- Quiet mode → "ok" or "error: type"

Use function injection (deps map) for CLI tests per existing pattern. Use `@moduletag :tmp_dir` for config file tests.

### Previous Story Learnings

From stories 1.4 and 1.5:
- **Function injection** for testing orchestration — deps map pattern in main.ex
- **FileSystem behaviour port** for file operations (but config is internal to .familiar/, so direct File is acceptable since it's our own managed directory)
- **Credo strict** — keep functions short, extract helpers for nested logic
- **Error convention** — `{:error, {atom_type, map_details}}` everywhere
- **Don't fight the formatter** — run `mix format` and accept results
- **Evidence in metadata** — JSON string in Entry.metadata field (not relevant here but shows the pattern)
- **DefaultFiles.install pattern** — check File.exists? before writing, File.mkdir_p! for directories

### Project Structure Notes

New files to create:
```
lib/familiar/
  └── config.ex                 # Config struct, parsing, validation, defaults
  └── config/
      └── generator.ex          # Default config.toml generation

test/familiar/
  ├── config_test.exs           # Config parsing and validation tests
  └── config/
      └── generator_test.exs    # Config generation tests
```

Modify:
- `lib/familiar/daemon/paths.ex` — add `config_path/0`
- `lib/familiar/knowledge/init_scanner.ex` — wire config generation after DefaultFiles.install
- `lib/familiar/cli/main.ex` — add `fam config` command with text formatter
- `lib/familiar/cli/output.ex` — add `:invalid_config` error message
- Existing tests may need minor updates for config-aware init pipeline

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 1, Story 1.6]
- [Source: _bmad-output/planning-artifacts/architecture.md — CLI entry point flow, per-project daemon scoping, data-driven config]
- [Source: _bmad-output/planning-artifacts/prd.md — FR7, FR7b, FR7c, FR78, config structure, language config example]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — notification model, config.toml keybindings]
- [Source: lib/familiar/cli/main.ex — auto-init at lines 82-95, existing JSON output]
- [Source: lib/familiar/cli/output.ex — JSON envelope implementation]
- [Source: lib/familiar/knowledge/init_scanner.ex — Init pipeline, DefaultFiles.install at line 103]
- [Source: lib/familiar/daemon/paths.ex — .familiar/ path resolution]
- [Source: lib/familiar/knowledge/command_validator.ex — Language detection for config generation]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

### Completion Notes List

- Created `Familiar.Config` module with `load/1`, `defaults/0`, `language_defaults/1`
- Config struct with 4 sections: provider, language, scan, notifications
- TOML parsing via `Toml.decode_file/1` with graceful error handling (missing file → defaults)
- Field-level validation: positive integers for timeout/max_files, booleans for enabled, strings for URLs/models
- Validation returns `{:error, {:invalid_config, %{field: ..., reason: ...}}}` with specific field paths
- Default language configs for Elixir and Go with test/build/lint commands, skip patterns, source extensions
- Created `Familiar.Config.Generator` to write `.familiar/config.toml` during init
- Generated config has detected language values populated, unknown languages get commented defaults
- Does not overwrite existing config files
- Wired config generation into InitScanner pipeline after DefaultFiles.install
- Added `config_path/0` to `Familiar.Daemon.Paths`
- Added `fam config` CLI command with text formatter showing all config sections
- Added `:invalid_config` error message to Output module
- Comprehensive JSON envelope audit: all 10 error types tested for proper `{"error": {"type", "message", "details"}}` structure
- Auto-init tested for config and health commands, failure propagation verified
- 30 new tests (327 total + 4 properties), 0 failures
- Credo strict: 0 issues

### File List

New files:
- lib/familiar/config.ex
- lib/familiar/config/generator.ex
- test/familiar/config_test.exs
- test/familiar/config/generator_test.exs

Modified files:
- lib/familiar/daemon/paths.ex (added config_path/0)
- lib/familiar/knowledge/init_scanner.ex (wired ConfigGenerator after DefaultFiles.install)
- lib/familiar/cli/main.ex (added config command, config_to_map, format_config_text, help text)
- lib/familiar/cli/output.ex (added :invalid_config error message)
- test/familiar/cli/main_test.exs (added config command tests, auto-init edge cases)
- test/familiar/cli/output_test.exs (added invalid_config tests, JSON envelope audit)
