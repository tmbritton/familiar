# Deferred Work

Items deferred from code reviews and other workflows. Triaged 2026-04-15.

## Active — will fix if pattern recurs

- **Manual CLI smoke test for `bin/fam`** (from 7.5-5) — live end-to-end run. Will be covered by the upcoming exploratory testing session.
- **`changeset_to_mcp_error` uses substring matching** (from 8-4) — dispatches on human-readable validation messages. Fragile but correct. Refactor when Ecto provides machine-readable error tags.
- **Hardcoded init response IDs 1/2 in Client** (from 8-3) — fragile but correct. Fix if protocol changes break it.
- **No integration test for malformed JSON during handshake** (from 8-5) — unit test covers it. Add at integration level if malformed-JSON bugs appear.
- **`tools/list` error response (id=2 error) not tested at integration level** (from 8-5) — unit test covers it. Add if silent-failure detection becomes a pattern.

## Dismissed — accepted risk or by-design

- **`bin/fam` walk-up makes nested subprojects require workaround** (from 7.5-8) — matches git behavior. Document `FAMILIAR_PROJECT_DIR=$(pwd) fam init`.
- **`validate_familiar_project/1` defined but never called** (from 7.5-8) — forward-looking API for daemon boot. auto-init dispatch handles the common case.
- **Walk-up swallows EACCES and dangling symlinks** (from 7.5-8) — would need `File.lstat/1` plumbing. Rare in practice.
- **`daemon_status_fn` default reaches into production DaemonManager** (from 7.5-8) — masked by `safe_call/2`. Test-only concern.
- **No shell-level integration test for `bin/fam` walk-up** (from 7.5-8) — add later if regressions appear.
- **`safe_call/2` catches `:exit` and swallows them** (from 7.5-8) — not urgent. Could surface via diagnostics field.
- **`bin/fam` uses logical `$(pwd)` instead of physical `pwd -P`** (from 7.5-8) — consistent with Elixir side. Fix if users report symlink confusion.
- **Env var with `..` components expands against wrong cwd** (from 7.5-8) — edge case. Fix if reported.
- **No integration test for `Paths.project_dir/0` zero-arg path** (from 7.5-8) — thin wrapper, low risk.
- **`default_files_test.exs` role prompt assertions only check substring** (from 7.6-1) — pre-existing style, stable wording.
- **docker-compose volume mount assumes `cd familiar`** (from 7.6-2) — documented in compose comments.
- **`reload_server/1` only works for DB-sourced servers** (from 8-3) — by design; config servers are not individually reloadable.
- **Config servers always `read_only: false`** (from 8-3) — config.toml doesn't parse read_only. Acceptable for checked-in project servers.
- **Read-only filtering test assertion gap** (from 8-3) — covered by 8-5 integration test which asserts specific tool names.
- **`fam mcp --help` not implemented** (from 8-4) — global help covers all subcommands.
- **`config_only_server?` double status fetch** (from 8-4) — performance only, not correctness.
- **`build_json_attrs` doesn't type-check `args`/`env`** (from 8-4) — schema changeset validates at insert time.
- **MCP CLI test coverage gaps** (from 8-4) — covered by 8-5 integration test.
- **No `quiet_summary` for MCP result shapes** (from 8-4) — consistent with existing behavior.

## Fixed — 2026-04-15 deferred item triage

- **FakePort module duplicated across 3 test files** (from 8-5) — extracted to `test/support/fake_mcp_server.ex`.
- **Handshake helpers duplicated across test files** (from 8-5) — extracted alongside FakePort to shared module.
- **Duplicate config.toml server names leak client processes** (from 8-3) — added `dedup_config_entries/1` with warning log.
- **ETS table ownership** (from 8-3) — investigated; table is owned by Application process in production (long-lived). No code change needed.
- **Docker image tag validity** (from 7.6-2) — original tag didn't exist. Updated to `hexpm/elixir:1.19.5-erlang-28.2-debian-bookworm-20260202-slim`.
