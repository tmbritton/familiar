---
name: project_cwd_audit
description: File.cwd!() audit — multiple modules default to Familiar source dir instead of project dir in CLI mode
type: project
---

Multiple modules use `File.cwd!()` as the default project directory. In CLI mode (via `bin/fam`), `cwd` is the Familiar source directory, not the user's project. All should use `Familiar.Daemon.Paths.project_dir()` which respects `FAMILIAR_PROJECT_DIR`.

**Known locations (as of 2026-04-09):**

- `workflow_runner.ex:116` — `list_workflows` familiar_dir default
- `tools.ex:166` — safety sandbox project_dir lookup
- `roles/roles.ex:174` — familiar_dir for role/skill loading
- `safety.ex:63,190,193` — safety extension sandbox root
- `openai_compatible_adapter.ex:220` — config.toml path lookup

**Already fixed:**
- `file_watcher.ex` — fixed to use `Paths.project_dir()`
- `tools.ex` file/command tools — fixed via `project_path()` and `project_cmd_opts()`
- `paths.ex:13` — this IS the canonical source, reads env var

**How to apply:** Replace `File.cwd!()` with `Paths.project_dir()` in each location. Add `alias Familiar.Daemon.Paths` where needed. Test that role loading, workflow parsing, and safety enforcement work in CLI mode.
