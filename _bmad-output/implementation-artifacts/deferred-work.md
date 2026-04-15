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

## Deferred from: code review of 7.6-2-sandboxing-warning-and-container (2026-04-14)

- **Docker image tag validity unverified** — `hexpm/elixir:1.19.5-erlang-28.3.2-debian-bookworm-20250317-slim` is a plausible tag but wasn't verified against Docker Hub. CI should confirm the tag exists before merge. If it doesn't, update to the closest available tag.
- **docker-compose volume mount assumes `cd familiar`** — `../:/workspace` mounts the repo root as workspace. Works correctly when running `docker compose` from the `familiar/` subdirectory as documented, but confusing if run from elsewhere. Not blocking — documented in compose comments.

## Deferred from: code review of 8-3-mcp-server-storage-and-extension (2026-04-15)

- **ETS table ownership** — table owned by extension loader process, not a long-lived process; orphan client processes possible on crash. Production init is single-threaded via ExtensionLoader so not immediate risk.
- **`reload_server/1` only works for DB-sourced servers** — config-sourced servers return `:not_found`. Story 8-4 scope.
- **Config servers always `read_only: false`** — `config.toml` has no `read_only` field parsed. Story 8-4 `add-json` scope.
- **Read-only filtering test has no assertion on which tools were registered** — need to verify filtered tools are actually excluded. Story 8-5 integration test scope.
- **Hardcoded init response IDs 1/2 in Client** — pre-existing from Story 8-2, fragile but correct.
- **Duplicate config.toml server names not deduplicated within config source** — second entry silently overwrites first ETS row, leaking first client process. Story 8-4 validation scope.

## Deferred from: code review of 8-4-fam-mcp-management-cli (2026-04-15)

- **`changeset_to_mcp_error` uses substring matching** — dispatches on human-readable validation messages ("already been taken", "fam_"). Fragile but correct. Refactor when schema errors gain machine-readable tags.
- **`fam mcp --help` not implemented** — no dedicated subcommand help page. Global help covers all subcommands adequately.
- **`config_only_server?` double status fetch** — makes redundant second call to `MCPClient.server_status()`. Performance only, not correctness.
- **`build_json_attrs` doesn't type-check `args`/`env`** — accepts non-list/non-map values. Story 8-3 schema changeset validates at insert time.
- **MCP CLI test coverage gaps** — no tests for `--show-env`, `--read-only`/`--disabled` flags via real parse path, config-only error via default code path. Story 8-5 integration test scope.
- **No `quiet_summary` for MCP result shapes** — all fall through to "ok". Consistent with existing behavior.

## Deferred from: code review of 8-5-mcp-client-integration-test (2026-04-15)

- **FakePort module duplicated across 3 test files** — `client_test.exs`, `mcp_client_test.exs`, and `mcp_integration_test.exs` all define identical `FakePort` GenServer. Extract to `test/support/fake_port.ex` when pattern stabilizes.
- **Handshake helpers duplicated across test files** — `complete_handshake/2`, `send_line/3` duplicated in same 3 files. Extract alongside FakePort.
- **No integration test for malformed JSON during handshake** — AC5 tests error response path but not syntactically invalid JSON. The `client_test.exs` unit test covers malformed line handling; adding to integration test is lower priority.
- **`tools/list` error response (id=2 error) not tested at integration level** — Client transitions to `:connected` with zero tools silently. Covered by unit test in `client_test.exs`. Add if silent-failure detection becomes a pattern.
