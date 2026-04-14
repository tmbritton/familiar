# Deferred Work

Items deferred from code reviews and other workflows. These are real but not blocking the current story.

## Deferred from: code review of 7.5-5-cwd-audit-project-paths (2026-04-10)

- **Manual CLI smoke test for `bin/fam`** (AC7) — live `cd /tmp/fresh-project && fam init && fam roles && fam workflows && fam chat` run to confirm `OpenAICompatibleAdapter.load_project_config/0` correctly resolves `.familiar/config.toml` from the project directory end-to-end. All backing behavior is unit-tested in `test/familiar/path_resolution_defaults_test.exs`; this is the final integration check before marking the story fully done.

## Deferred from: code review of 7.5-8-project-dir-resolution-hardening (2026-04-10)

- **`bin/fam` walk-up makes `fam init` for nested subprojects require a workaround** — `cd ~/work/big-project/sub && fam init` walks up to the outer project's `.familiar/`, reports "already initialized," and refuses. Reason for defer: matches git's nested-repo behavior; document `FAMILIAR_PROJECT_DIR=$(pwd) fam init` workaround instead.
- **`validate_familiar_project/1` is defined but never called by production code** — AC4 said "commands that require an initialized project should call this," but the existing auto-init dispatch at `main.ex:200-213` already handles the "not initialized" case by running `fam init` first and retrying. Wiring `validate_familiar_project/1` in would regress that auto-init behavior. The helper stays as a forward-looking API for callers (like daemon boot) that should error rather than auto-init; wiring it in is a separate decision.
- **Walk-up swallows EACCES and dangling symlinks as "not a match"** — `File.dir?/1` returns `false` for both "not there" and "permission denied" so walk-up can silently climb past a real project root whose `.familiar/` is readable by someone else. Would need `File.lstat/1` plumbing to distinguish. Rare in practice.
- **`daemon_status_fn` default reaches into production `DaemonManager`** — The fallback when no dep is injected hits real GenServer state, masked by `safe_call/2`. Symptom of a broader test-wiring issue; not blocking. Revisit for Epic 8 MCP client work where clean `deps` will matter more.
- **No shell-level integration test for `bin/fam` walk-up** — All Elixir tests inject `cwd_getter`. A `bash bin/fam where` integration test would be useful but requires test harness work (CI invocation, daemon state isolation). Add later if bin/fam regressions become a pattern.
- **`safe_call/2` catches `:exit` from GenServer timeouts and swallows them** — `catch _, _ -> fallback` masks a stopped GenServer as `:stopped`. Could surface via a `diagnostics` field in the `fam where` output but not urgent.
- **`bin/fam` uses logical `$(pwd)` instead of physical `pwd -P`** — Diverges from git's behavior on symlink paths but matches the Elixir-side textual walk-up, so the two sides are at least consistent. Fix if users report symlink-related confusion.
- **Env var with `..` components expands against wrong cwd post-bootstrap** — `FAMILIAR_PROJECT_DIR=../other fam cmd` resolves against `FAMILIAR_ROOT` (the Familiar source checkout that `bin/fam` cd's into) instead of the user's shell cwd. Fix would require bin/fam to pre-expand or capture the original pwd. Edge case.
- **No integration test for `Paths.project_dir/0` zero-arg walk-up path** — The resolve-level tests cover the logic via injected opts; the zero-arg production path isn't exercised with walk-up. `Paths.project_dir/0` is a thin wrapper, so the risk is low.

## Deferred from: code review of 7.6-1-remove-safety-extension (2026-04-14)

- **`default_files_test.exs` role prompt assertions only check substring** — `assert role.system_prompt =~ "Sandboxing"` verifies the section header exists but not the substantive guidance text ("container or equivalent sandbox"). Pre-existing test style throughout the file — all role tests use `=~` substring checks. Low risk since the wording is stable.
