# Deferred Work

Items deferred from code reviews and other workflows. These are real but not blocking the current story.

## Deferred from: code review of 7.5-5-cwd-audit-project-paths (2026-04-10)

- **Manual CLI smoke test for `bin/fam`** (AC7) — live `cd /tmp/fresh-project && fam init && fam roles && fam workflows && fam chat` run to confirm `OpenAICompatibleAdapter.load_project_config/0` correctly resolves `.familiar/config.toml` from the project directory end-to-end. All backing behavior is unit-tested in `test/familiar/path_resolution_defaults_test.exs`; this is the final integration check before marking the story fully done.
