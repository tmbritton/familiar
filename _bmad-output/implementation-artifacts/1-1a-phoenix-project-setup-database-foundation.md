# Story 1.1a: Phoenix Project Setup & Database Foundation

Status: done

## Story

As a developer,
I want a properly configured Phoenix project with SQLite and sqlite-vec working,
so that all subsequent stories build on a solid, compilable foundation.

## Acceptance Criteria

1. **Project Generation:** `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard` executed and post-generation modifications applied
2. **Compilation:** Project compiles with zero warnings (`mix compile --warnings-as-errors`)
3. **Tailwind Stripped:** Tailwind CSS configuration and dependencies removed entirely
4. **Default Layout Stripped:** Phoenix default layout (navbar, sidebar, hero) replaced with minimal root layout
5. **Dependencies Added:** `sqlite_vec`, `req`, `mox`, `stream_data`, `boundary`, `toml`, `yaml_elixir` added to `mix.exs`
6. **License:** AGPL-3.0 license file present
7. **Formatter:** `.formatter.exs` configured, `mix format` passes
8. **Credo:** `.credo.exs` configured with strict mode, `mix credo --strict` passes
9. **Ecto Repo:** SQLite3 database created on startup, sqlite-vec extension loads successfully
10. **Vector Operations:** Can insert a Float32 vector into a sqlite-vec virtual table and retrieve by cosine similarity
11. **Tests Pass:** `mix test` passes with Ecto sandbox properly configured

## Tasks / Subtasks

- [x] Task 1: Generate Phoenix project (AC: #1)
  - [x] Run `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard`
  - [x] Verify generated project compiles
- [x] Task 2: Strip Tailwind and default layout (AC: #3, #4)
  - [x] Remove `tailwind` and `heroicons` deps from `mix.exs`
  - [x] Remove Tailwind config from `config/config.exs` and `config/dev.exs` watchers
  - [x] Remove Tailwind-related aliases from `mix.exs`
  - [x] Replace `root.html.heex` with minimal layout (no navbar/sidebar/hero/theme toggle)
  - [x] Replace `layouts.ex` with minimal zero-chrome version
  - [x] Replace `app.css` with empty CSS (LiveView display:contents rule only)
  - [x] Remove vendor files (daisyui.js, daisyui-theme.js, heroicons.js)
  - [x] Replace home.html.heex with minimal content
- [x] Task 3: Add dependencies (AC: #5)
  - [x] Add to `mix.exs` deps: sqlite_vec, req, mox, stream_data, credo, boundary, toml, yaml_elixir
  - [x] Run `mix deps.get`
  - [x] Verify all deps compile
- [x] Task 4: Configure Ecto Repo with sqlite-vec (AC: #9, #10)
  - [x] Configure `Familiar.Repo` with `load_extensions: [SqliteVec.path()]` in `init/2`
  - [x] Create migration with `vec0` virtual table (Float32 3-dimensional vectors)
  - [x] Write tests: extension loads, vector insert + cosine similarity query, ranked results
  - [x] Note: vectors passed as JSON arrays (not binary) to vec0 tables
- [x] Task 5: Configure formatting and linting (AC: #7, #8)
  - [x] `.formatter.exs` configured (Phoenix default)
  - [x] `.credo.exs` generated with `mix credo gen.config`
  - [x] Fixed credo issues in generated code (alias ordering, parentheses, nested modules)
  - [x] `mix format` and `mix credo --strict` pass clean
- [x] Task 6: License and project metadata (AC: #6)
  - [x] AGPL-3.0 LICENSE file downloaded from gnu.org
  - [x] `mix.exs` updated with description and license metadata
- [x] Task 7: Verify full test suite (AC: #2, #11)
  - [x] `mix compile --warnings-as-errors` passes
  - [x] `mix test` — 8 tests, 0 failures
  - [x] `mix format --check-formatted` passes
  - [x] `mix credo --strict` — no issues

## Dev Notes

### Architecture Compliance

**Source:** [architecture.md — Starter Template Evaluation]

- **Initialization command:** `mix phx.new familiar --database sqlite3 --no-mailer --no-dashboard`
- **Phoenix version:** 1.8.5 (verify with `mix hex.info phoenix`)
- **Phoenix LiveView:** 1.1.28 (generated as dependency)
- **Ecto adapter:** `ecto_sqlite3` (latest, generated)
- **exqlite:** 0.35.0 (SQLite3 NIF driver)
- **sqlite_vec:** 0.1.0 (sqlite-vec extension wrapper for Ecto Float32 vectors)

### sqlite-vec Integration (Critical Spike)

**Source:** [architecture.md — Data Architecture]

This story includes the sqlite-vec spike that de-risks the thesis-critical context retrieval path. The spike must prove:
1. Embedding vectors can be inserted into sqlite-vec virtual tables via Ecto
2. Cosine similarity queries work and return ranked results
3. Performance is acceptable at small scale (will be validated at 200+ entries in Story 1.7)

**sqlite-vec approach:** The `sqlite_vec` hex package (v0.1.0) provides Ecto custom types for Float32 vectors. Use the package's documented approach for:
- Loading the extension in Repo `init/2`
- Creating virtual tables for vector search
- Inserting embeddings as Float32 arrays
- Querying by `vec_distance_cosine`

**If `sqlite_vec` package approach doesn't work:** Fall back to raw SQL via `Ecto.Adapters.SQL.query!/3` for vector operations. The hex package is preferred but the extension itself is the critical dependency, not the Elixir wrapper.

### Post-Generation Modifications Checklist

**Source:** [architecture.md — Post-Generation Modifications]

1. ✅ Strip Tailwind CSS configuration and dependencies
2. ✅ Strip default Phoenix layout — zero-chrome per UX spec
3. ✅ Add `sqlite_vec` dependency and configure extension loading in Repo
4. ✅ Add `req` dependency for CLI HTTP client (used in later stories)
5. ❌ Configure project for daemon architecture — **deferred to Story 1.3a**
6. ❌ Add CLI entry point module — **deferred to Story 1.3b**
7. ✅ Replace license with AGPL-3.0
8. ❌ Configure `.familiar/` project directory structure — **deferred to Story 1.4**

### What NOT to Do in This Story

- **Do NOT create domain context modules** — that's Story 1.1b
- **Do NOT create behaviour ports or Mox mocks** — that's Story 1.1b
- **Do NOT configure the daemon or supervision tree** — that's Story 1.3a
- **Do NOT create any Ecto schemas beyond the sqlite-vec test table** — schemas are created in their respective epics
- **Do NOT add API routes or controllers** — that's Story 1.3a
- **Do NOT create `.familiar/` directory structure** — that's Story 1.4

### Elixir/Phoenix Conventions

**Source:** [architecture.md — Implementation Patterns]

- Module naming: `CamelCase` — `Familiar.Repo`, `Familiar.Application`
- File naming: `snake_case.ex` matching module — `repo.ex`, `application.ex`
- Database: plural snake_case tables, snake_case columns, Ecto default timestamps
- Formatting: `mix format` — no exceptions, no overrides
- Test files: mirror `lib/` structure in `test/`, suffix `_test.exs`

### Project Structure After This Story

```
familiar/
├── .formatter.exs
├── .gitignore
├── .credo.exs
├── mix.exs                           # Phoenix + deps configured
├── mix.lock
├── README.md
├── LICENSE                           # AGPL-3.0
├── config/
│   ├── config.exs                    # Shared config, Repo config
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── familiar/
│   │   ├── application.ex            # Default Phoenix Application
│   │   └── repo.ex                   # Ecto Repo with sqlite-vec extension
│   ├── familiar_web/
│   │   ├── endpoint.ex               # Default Phoenix endpoint
│   │   ├── router.ex                 # Default Phoenix router (minimal)
│   │   ├── components/               # Stripped — minimal layout only
│   │   └── controllers/              # Default page controller
│   └── familiar_web.ex
├── priv/
│   └── repo/
│       └── migrations/               # sqlite-vec test migration
├── test/
│   ├── test_helper.exs
│   ├── support/
│   │   └── data_case.ex              # Ecto sandbox setup
│   └── familiar/
│       └── repo_test.exs             # sqlite-vec vector operations test
└── assets/
    └── css/
        └── app.css                   # Empty — Tailwind stripped
```

### Testing Requirements

- `test/familiar/repo_test.exs` — Verify sqlite-vec extension loads, vector insert works, cosine similarity query returns ranked results
- All generated Phoenix tests still pass after modifications
- `mix compile --warnings-as-errors` passes
- `mix format --check-formatted` passes
- `mix credo --strict` passes

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Starter Template Evaluation]
- [Source: _bmad-output/planning-artifacts/architecture.md#Data Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#Implementation Patterns & Consistency Rules]
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure & Boundaries]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1a]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- sqlite-vec vectors must be passed as JSON arrays (e.g., "[1.0, 0.0, 0.0]"), not binary — initial attempt with SqliteVec.Float32.to_binary() failed
- Phoenix 1.8.5 generates with daisyUI + Tailwind 4, not just plain Tailwind — required removing daisyui.js, daisyui-theme.js, heroicons.js vendor files
- Credo found issues in generated Phoenix code — fixed alias ordering, parentheses on no-arg functions, nested module aliases

### Completion Notes List

- Phoenix 1.8.5 project generated with SQLite3 at `familiar/` subdirectory
- Tailwind, daisyUI, heroicons fully stripped — zero-chrome minimal layout
- sqlite-vec v0.1.5 loads successfully via `SqliteVec.path()` in Repo `init/2`
- Vector similarity search proven: insert JSON vectors, query with MATCH + ORDER BY distance
- All 8 deps added (sqlite_vec, req, mox, stream_data, credo, boundary, toml, yaml_elixir)
- AGPL-3.0 license installed
- 8 tests pass, 0 failures, format clean, credo strict clean

### File List

- familiar/mix.exs (modified — deps, metadata, aliases)
- familiar/config/config.exs (modified — removed tailwind config)
- familiar/config/dev.exs (modified — removed tailwind watcher)
- familiar/lib/familiar/repo.ex (modified — sqlite-vec extension loading)
- familiar/lib/familiar/application.ex (modified — credo fix)
- familiar/lib/familiar_web.ex (modified — alias ordering)
- familiar/lib/familiar_web/components/layouts.ex (rewritten — zero-chrome)
- familiar/lib/familiar_web/components/layouts/root.html.heex (rewritten — minimal)
- familiar/lib/familiar_web/components/core_components.ex (modified — icon stub, alias)
- familiar/lib/familiar_web/controllers/page_html/home.html.heex (rewritten — minimal)
- familiar/assets/css/app.css (rewritten — empty, no Tailwind)
- familiar/assets/vendor/heroicons.js (deleted)
- familiar/assets/vendor/daisyui.js (deleted)
- familiar/assets/vendor/daisyui-theme.js (deleted)
- familiar/priv/repo/migrations/20260401194757_create_vec_test_table.exs (new)
- familiar/test/familiar/repo_test.exs (new — 3 sqlite-vec tests)
- familiar/test/familiar_web/controllers/page_controller_test.exs (modified — updated assertion)
- familiar/test/support/data_case.ex (modified — credo fix)
- familiar/LICENSE (new — AGPL-3.0)
- familiar/.credo.exs (new — generated)
