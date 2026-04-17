# Story 9-5: Loadable System Templates

Status: done

## Story

As a Familiar user,
I want system-level prompts and configuration templates stored as editable files in `.familiar/system/`,
So that I can tailor extraction, system behavior, and other miscellaneous concerns to my domain without touching Elixir code.

## Acceptance Criteria

1. **AC1: Default template exists.** `familiar/priv/defaults/system/extractor.md` contains the extraction prompt with template variables `{{file_path}}`, `{{content}}`, and `{{valid_types}}`.

2. **AC2: DefaultFiles installs system/ subdir.** `DefaultFiles.install/1` copies `priv/defaults/system/` to `.familiar/system/` with the same skip-if-exists semantics as roles/skills/workflows.

3. **AC3: Extractor loads custom template.** `Extractor.build_prompt/2` checks for `.familiar/system/extractor.md` in the project dir. If found, reads it and interpolates template variables. If not found, falls back to `priv/defaults/system/extractor.md`.

4. **AC4: Template variable interpolation.** `{{file_path}}` resolves to the file path argument, `{{content}}` resolves to the (truncated) content argument, `{{valid_types}}` resolves to `Entry.default_types/0 |> Enum.map_join(", ", &inspect/1)`.

5. **AC5: Tests — custom template loaded.** Test that when `.familiar/system/extractor.md` exists in the project dir, `build_prompt/2` uses its content instead of the default.

6. **AC6: Tests — fallback to default.** Test that when no custom template exists, `build_prompt/2` falls back to the compiled-in default from `priv/defaults/system/extractor.md`.

7. **AC7: Tests — variable interpolation.** Test that `{{file_path}}`, `{{content}}`, and `{{valid_types}}` are all replaced in the output prompt.

8. **AC8: DefaultFiles tests.** Test that `install/1` creates `.familiar/system/extractor.md` and that it skips if file already exists.

9. **AC9: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

10. **AC10: Stress-tested.** `extractor_test.exs` and `default_files_test.exs` pass 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Create `priv/defaults/system/extractor.md` (AC: 1)
  - [x] Extract the prompt string from `Extractor.build_prompt/2` (lines 75–96)
  - [x] Write it as a markdown file with `{{file_path}}`, `{{content}}`, `{{valid_types}}` template variables
  - [x] Preserve the exact prompt semantics (JSON array instruction, rules, truncation note)

- [x] Task 2: Update `DefaultFiles` to include `system/` subdir (AC: 2)
  - [x] Add `"system"` to `@subdirs` list (currently `~w(workflows roles skills)`)
  - [x] Verify the compile-time `@defaults` comprehension picks up `system/extractor.md` automatically (it iterates `@subdirs`)
  - [x] Added `default_content/2` public function to look up compiled defaults by subdir/filename

- [x] Task 3: Add template interpolation to `Extractor.build_prompt/2` (AC: 3, 4)
  - [x] Uses `Paths.familiar_dir/0` to resolve the `.familiar/` path (standard pattern used by other modules)
  - [x] Check for `.familiar/system/extractor.md` — if exists, read it; else fall back to compiled default via `DefaultFiles.default_content/2`
  - [x] Interpolate `{{file_path}}`, `{{content}}` (truncated to 4000 chars), `{{valid_types}}` (from `Entry.default_types/0`)
  - [x] Replace the current hardcoded string in `build_prompt/2` with the template-based approach

- [x] Task 4: Update extractor tests (AC: 5, 6, 7)
  - [x] Test: custom `.familiar/system/extractor.md` is used when present
  - [x] Test: fallback to default template when custom file absent
  - [x] Test: all three template variables are interpolated correctly
  - [x] Ensure existing `build_prompt/2` tests still pass (the output content should be equivalent)

- [x] Task 5: Update DefaultFiles tests (AC: 8)
  - [x] Test: `install/1` creates `system/extractor.md` in the target dir (byte-for-byte match)
  - [x] Test: `install/1` skips `system/extractor.md` if it already exists
  - [x] Test: `default_content/2` returns compiled content for system/extractor.md
  - [x] Test: `default_content/2` returns `:error` for non-existent file
  - [x] Updated `priv_defaults_path/0` test to check `system/` subdir exists

- [x] Task 6: Toolchain verification (AC: 9)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1349 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 7: Stress-test (AC: 10)
  - [x] 50x on `extractor_test.exs` — 51/51 clean
  - [x] 50x on `default_files_test.exs` — 51/51 clean

## Dev Notes

### Current `build_prompt/2` (extractor.ex lines 74–96)

```elixir
@spec build_prompt(String.t(), String.t()) :: String.t()
def build_prompt(file_path, content) do
  """
  Analyze this source file and produce knowledge entries as a JSON array.
  Each entry must have "type", "text", and "source_file" fields.

  Valid types: #{Entry.default_types() |> Enum.map_join(", ", &~s("#{&1}"))}

  Rules:
  - Describe what the code DOES in natural language prose
  - Do NOT include raw code snippets
  - Do NOT include secret values (API keys, tokens, passwords)
  - Focus on purpose, patterns, dependencies, and architectural decisions
  - Keep each entry concise (1-3 sentences)

  File: #{file_path}
  Content:
  \```
  #{String.slice(content, 0, 4000)}
  \```

  Respond with ONLY a JSON array of entry objects, no other text.
  """
end
```

This entire string becomes the content of `priv/defaults/system/extractor.md`, with Elixir interpolations replaced by template variables:
- `#{Entry.default_types() |> ...}` → `{{valid_types}}`
- `#{file_path}` → `{{file_path}}`
- `#{String.slice(content, 0, 4000)}` → `{{content}}`

### Current `DefaultFiles` structure (default_files.ex)

```elixir
@subdirs ~w(workflows roles skills)

@defaults (for subdir <- @subdirs,
               filename <- File.ls!(...),
               String.ends_with?(filename, ".md") do
             {subdir, filename, File.read!(path)}
           end)
```

Adding `"system"` to `@subdirs` is the only change needed — the comprehension and install loop are already generic.

### Finding the project dir

Search codebase for how other modules resolve the `.familiar/` directory path. Look at:
- `Familiar.Config` or `Familiar.ProjectDir` for the resolution logic
- Check `Application.get_env(:familiar, :project_dir)` usage
- The extractor currently receives no project dir context — you'll need to thread it in or look it up

### Template interpolation approach

Use `String.replace/3` for the three known variables — no need for a full template engine:

```elixir
template
|> String.replace("{{file_path}}", file_path)
|> String.replace("{{content}}", String.slice(content, 0, 4000))
|> String.replace("{{valid_types}}", Entry.default_types() |> Enum.map_join(", ", &inspect/1))
```

### Compiled-in fallback

The `@defaults` comprehension at compile time reads `priv/defaults/system/extractor.md` into the module. For the fallback, you can either:
1. Store the compiled default in a module attribute and use it directly
2. Or add a public function `DefaultFiles.default_content("system", "extractor.md")` that returns the compiled content

Option 1 is simpler — add a `@default_extractor_template` attribute in Extractor that reads from priv at compile time, similar to how DefaultFiles does it. But this duplicates the compile-time read. Option 2 keeps DefaultFiles as the single source of compiled defaults.

### What NOT to touch

- **Hygiene prompt** — `build_success_prompt` in hygiene.ex is also hardcoded, but that's future work (not in this story's scope)
- **Schema or migrations** — no database changes
- **Entry module** — already exposes `default_types/0` from Story 9-4
- **Config module** — unless needed to resolve project dir

### Previous story patterns (Story 9-4)

- Code review caught inconsistencies between modules (hardcoded types in Hygiene prompt) — verify the template content matches exactly what `build_prompt/2` currently produces
- Credo flags deeply nested module references — use aliases
- `mix format` may auto-wrap long lines — run early
- Two files outside story scope needed updating in 9-4 — grep for any callers of `build_prompt/2` beyond extractor itself

### Callers of `build_prompt/2`

Grep for `build_prompt` to find all callers:
- `extractor.ex` lines 42, 61 — internal calls
- `extractor_test.exs` lines 137, 143, 150 — test calls

### `priv/defaults/` structure after this story

```
priv/defaults/
├── roles/          (7 files — existing)
├── skills/         (12 files — existing)
├── system/         (NEW)
│   └── extractor.md
└── workflows/      (3 files — existing)
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 9-5] — Epic scope definition
- [Source: familiar/lib/familiar/knowledge/extractor.ex:74-96] — Current hardcoded prompt
- [Source: familiar/lib/familiar/knowledge/default_files.ex:11-23] — DefaultFiles compile-time read and @subdirs
- [Source: _bmad-output/implementation-artifacts/9-4-open-entry-type-source-validation.md] — Previous story patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- `mix format` auto-corrected long lines in extractor_test.exs (tmp_dir and custom_template assignments)
- Used `DefaultFiles.default_content/2` (Option 2) for compiled-in fallback — avoids duplicating compile-time reads in Extractor

### Completion Notes List

- Created `priv/defaults/system/extractor.md` with template variables `{{file_path}}`, `{{content}}`, `{{valid_types}}`
- Added `"system"` to `DefaultFiles.@subdirs` — compile-time comprehension and install loop pick it up automatically
- Added `DefaultFiles.default_content/2` public function to look up any compiled default by subdir/filename
- Replaced hardcoded prompt in `Extractor.build_prompt/2` with template loading: custom `.familiar/system/extractor.md` → compiled default fallback → `String.replace/3` interpolation
- Uses `Paths.familiar_dir/0` for project dir resolution (standard pattern)
- 17 extractor tests (was 14, +3 new), 28 default_files tests (was 24, +4 new)
- Test count: 1349 tests + 16 properties, 0 failures

### File List

**New:**
- familiar/priv/defaults/system/extractor.md (extraction prompt template)

**Modified:**
- familiar/lib/familiar/knowledge/default_files.ex (added "system" to @subdirs, added default_content/2)
- familiar/lib/familiar/knowledge/extractor.ex (template loading + interpolation replaces hardcoded prompt)
- familiar/test/familiar/knowledge/extractor_test.exs (+3 tests: custom template, fallback, interpolation)
- familiar/test/familiar/knowledge/default_files_test.exs (+4 tests: system install, skip-if-exists, default_content/2, priv subdir check)

### Change Log

- 2026-04-17: Story 9-5 implemented — extraction prompt moved to loadable template in `.familiar/system/`
