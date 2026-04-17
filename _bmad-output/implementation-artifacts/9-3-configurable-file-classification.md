# Story 9-3: Configurable File Classification

Status: review

## Story

As a Familiar user working on a non-code project,
I want file classification rules to come from my config rather than hardcoded Elixir lists,
So that I can index PDFs, manuscripts, research notes, or any file type relevant to my domain.

## Acceptance Criteria

1. **AC1: Config struct extended.** `Familiar.Config` defstruct includes an `indexing` field containing maps for `skip_dirs`, `skip_extensions`, `skip_files`, `source_extensions`, `config_files`, `config_extensions`, `doc_extensions`, `test_patterns`. Defaults match the current hardcoded values in `file_classifier.ex`.

2. **AC2: Config parsing.** `Familiar.Config.load/1` parses the `[indexing]` section from config.toml. Missing keys fall back to defaults. Invalid values (e.g., non-list for `skip_dirs`) produce `{:error, {:invalid_config, ...}}`.

3. **AC3: Config template.** `ConfigGenerator.generate_default/1` includes a commented `[indexing]` section with all 8 keys showing their default values.

4. **AC4: FileClassifier accepts config.** `FileClassifier.classify/2` accepts an `indexing` option containing the config map. When provided, it uses the config values instead of module attributes. When not provided (nil or missing key), it falls back to the module attributes (backward compatible).

5. **AC5: Significance uses config.** `FileClassifier.significance/2` accepts an optional indexing config to determine source_extensions, config_files, config_extensions, doc_extensions, and test_patterns. Falls back to module attributes when not provided.

6. **AC6: Callers updated.** `InitScanner.scan_files/2` and `InitScanner.walk_entry/3` pass the loaded config's indexing rules to `FileClassifier`. If no config is loaded (init hasn't completed yet), module attribute defaults are used.

7. **AC7: Tests cover both paths.** `file_classifier_test.exs` tests: (a) default behavior unchanged when no config passed, (b) custom config overrides (e.g., `.pdf` in source_extensions causes `:index`), (c) partial config (only some keys) merges with defaults, (d) config with empty lists still works.

8. **AC8: Config test.** `config_test.exs` includes tests for parsing the `[indexing]` section — valid values, missing section (defaults), and invalid values (error).

9. **AC9: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

10. **AC10: Stress-tested.** `file_classifier_test.exs` and `config_test.exs` pass 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Add indexing field to Config struct and parsing (AC: 1, 2)
  - [x] Add `indexing` field to `defstruct` in `config.ex` with default values matching file_classifier.ex
  - [x] Add `validate_indexing/1` and `merge_indexing_defaults/1` private functions
  - [x] Wire `validate_indexing/1` into `validate_and_build/1`
  - [x] Handle missing section (return defaults), partial keys (merge with defaults), invalid types (return error)
  - [x] Note: test_patterns stored as strings (not regexes) since Regex not allowed in defstruct defaults

- [x] Task 2: Update config generator template (AC: 3)
  - [x] Add `indexing_section/0` private function to `generator.ex`
  - [x] All 8 keys listed with their default values, commented out
  - [x] Wire into `build_config_content/0`

- [x] Task 3: Update FileClassifier to accept indexing config (AC: 4, 5)
  - [x] Update `classify/2` to read indexing config from opts via `idx/3` helper
  - [x] When indexing config present, use its values for skip_dirs, skip_extensions, skip_files
  - [x] When not present, fall back to module attributes (backward compatible)
  - [x] Update `significance/2` with optional indexing config via opts
  - [x] `ensure_regexes/1` compiles string patterns to regexes for test_patterns
  - [x] Update `prioritize/3` and `prioritize_with_info/3` to pass opts through

- [x] Task 4: Update InitScanner callers (AC: 6)
  - [x] `scan_files/2`: reads `:indexing` from opts, passes to classify and prioritize
  - [x] `walk_tree/3` and `walk_entry/4`: pass classify_opts through
  - [x] Graceful fallback: if no indexing in opts, empty classify_opts uses module defaults

- [x] Task 5: Update file_classifier_test.exs (AC: 7)
  - [x] All 39 existing tests preserved and passing (default behavior)
  - [x] Added "classify/2 with custom indexing config" (7 tests)
  - [x] Added "significance/2 with custom indexing config" (3 tests)

- [x] Task 6: Update config_test.exs (AC: 8)
  - [x] Test: `[indexing]` section parsed correctly (source_extensions, skip_dirs)
  - [x] Test: missing `[indexing]` section → defaults
  - [x] Test: partial indexing keys → merge with defaults
  - [x] Test: test_patterns parsed as strings
  - [x] Test: invalid indexing value (string instead of list) → error
  - [x] Test: non-string elements in list → error
  - [x] Updated defaults test to include indexing assertions

- [x] Task 7: Toolchain verification (AC: 9)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1326 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 8: Stress-test (AC: 10)
  - [x] 50x run on `file_classifier_test.exs` — 51/51 clean
  - [x] 50x run on `config_test.exs` — 51/51 clean

## Dev Notes

### Current FileClassifier module attributes (lines 10-26)

These become the default values in the Config struct's `indexing` field:

```elixir
@skip_dirs ~w(.git/ vendor/ node_modules/ _build/ deps/ .elixir_ls/ .familiar/
    __pycache__/ .tox/ .mypy_cache/ target/ dist/ build/)
@skip_extensions ~w(.beam .pyc .pyo .class .o .so .dylib .min.js .min.css .map)
@skip_files ~w(go.sum mix.lock package-lock.json yarn.lock Cargo.lock poetry.lock Gemfile.lock)
@source_extensions ~w(.ex .exs .go .py .ts .tsx .js .jsx .rb .rs .java .c .cpp .h .hpp .cs .swift .kt)
@config_files ~w(mix.exs package.json Cargo.toml pyproject.toml Gemfile Makefile CMakeLists.txt)
@config_extensions ~w(.toml .yaml .yml .json .xml .ini .cfg)
@doc_extensions ~w(.md .txt .rst .adoc)
@test_patterns [~r{test/}, ~r{spec/}, ~r{_test\.}, ~r{_spec\.}]
```

**Keep module attributes as fallback defaults.** They're used when no config is passed (backward compat). Don't delete them.

### Config struct design

Add `indexing` field to the existing defstruct. The indexing map should mirror the module attributes:

```elixir
defstruct ...,
          indexing: %{
            skip_dirs: ~w(.git/ vendor/ node_modules/ ...),
            skip_extensions: ~w(.beam .pyc ...),
            skip_files: ~w(go.sum mix.lock ...),
            source_extensions: ~w(.ex .exs .go ...),
            config_files: ~w(mix.exs package.json ...),
            config_extensions: ~w(.toml .yaml ...),
            doc_extensions: ~w(.md .txt ...),
            test_patterns: ["test/", "spec/", "_test.", "_spec."]
          }
```

**Note on test_patterns:** In the module attributes, `@test_patterns` are regex values (`~r{test/}`). In TOML config, they'll be strings (`"test/"`). The `validate_indexing/1` function should compile strings to regexes. The Config struct stores them as regexes for consistency with how `test_file?/1` uses them.

### FileClassifier.classify/2 opts pattern

Currently `classify/2` already accepts opts with `:skip_dirs`. Extend this to accept `:indexing`:

```elixir
def classify(path, opts \\ []) do
  indexing = Keyword.get(opts, :indexing)
  skip_dirs = get_indexing(indexing, :skip_dirs, @skip_dirs)
  extra = Keyword.get(opts, :skip_dirs, [])
  all_skip_dirs = skip_dirs ++ extra
  ...
end
```

Helper:
```elixir
defp get_indexing(nil, _key, default), do: default
defp get_indexing(indexing, key, default), do: Map.get(indexing, key, default)
```

### Callers of FileClassifier (3 call sites in init_scanner.ex)

1. **Line 38:** `Enum.filter(&(FileClassifier.classify(&1) == :index))` — needs indexing config
2. **Line 42:** `FileClassifier.prioritize_with_info(all_files, max_files)` — needs indexing config for significance
3. **Line 264:** `FileClassifier.classify(entry <> "/") != :skip` — needs indexing config

InitScanner receives opts but doesn't currently load config. Add config loading:
- Accept `:indexing` in opts (passed from callers who already loaded config)
- If not in opts, try to load from `.familiar/config.toml` if it exists
- During initial scan (before config.toml exists), use defaults

### Config generator template

Add a commented `[indexing]` section showing all defaults. Pattern matches existing sections:

```toml
[indexing]
# skip_dirs = [".git/", "vendor/", "node_modules/", ...]
# skip_extensions = [".beam", ".pyc", ".pyo", ...]
# skip_files = ["go.sum", "mix.lock", ...]
# source_extensions = [".ex", ".exs", ".go", ...]
# config_files = ["mix.exs", "package.json", ...]
# config_extensions = [".toml", ".yaml", ".yml", ...]
# doc_extensions = [".md", ".txt", ".rst", ".adoc"]
# test_patterns = ["test/", "spec/", "_test.", "_spec."]
```

### What NOT to touch

- **Module attributes in file_classifier.ex** — keep as fallback defaults, don't delete
- **`language` section in config** — that's a separate concern (language detection was removed in a prior story, but the section may still exist)
- **FileClassifier public API arity** — `classify/2` stays as `/2` with opts. Don't change to `/3`.
- **prioritize/2 and prioritize_with_info/2 public API** — keep arities, pass config through internally

### Previous story patterns (Story 9-2)

- Compile-time embedding pattern for priv files
- 50x stress testing on all touched test files
- Full toolchain check including dialyzer
- Story file updated with completion notes, file list, change log
- Code review caught false positives but also real issues — verify @external_resource-like patterns work

### Project Structure Notes

- Config files: `lib/familiar/config.ex`, `lib/familiar/config/generator.ex`
- Config test: `test/familiar/config_test.exs` (verify exists)
- FileClassifier: `lib/familiar/knowledge/file_classifier.ex` (130 lines)
- FileClassifier test: `test/familiar/knowledge/file_classifier_test.exs` (196 lines, 48 tests)
- InitScanner: `lib/familiar/knowledge/init_scanner.ex` (282 lines)

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 9-3] — Epic scope definition
- [Source: familiar/lib/familiar/knowledge/file_classifier.ex:10-26] — Current hardcoded module attributes
- [Source: familiar/lib/familiar/config.ex:11-20] — Current Config defstruct
- [Source: familiar/lib/familiar/config/generator.ex:29-42] — Config template builder
- [Source: familiar/lib/familiar/knowledge/init_scanner.ex:38,42,264] — FileClassifier call sites
- [Source: _bmad-output/implementation-artifacts/9-2-default-files-to-priv.md] — Previous story patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Regex values not allowed in defstruct defaults (Elixir 1.19 restriction). Stored test_patterns as strings in Config, compiled to regexes in FileClassifier via `ensure_regexes/1`.
- Credo flagged nesting depth in `validate_indexing` and `validate_indexing_lists`. Refactored: extracted `merge_indexing_defaults/1` and `validate_string_list/2`.
- `walk_tree/3` default arg warning: removed default since `scan_files` always passes classify_opts explicitly.

### Completion Notes List

- Added `indexing` field to Config defstruct with 8 keys matching FileClassifier module attributes
- Added `validate_indexing/1`, `merge_indexing_defaults/1`, `validate_indexing_lists/1`, `validate_string_list/2` to Config
- Added `indexing_section/0` to ConfigGenerator — all 8 keys shown commented with defaults
- Rewrote FileClassifier: `classify/2`, `significance/2`, `prioritize/3`, `prioritize_with_info/3` all accept `:indexing` opt
- Added `idx/3` helper for config-or-default lookup, `ensure_regexes/1` for string→regex compilation
- Updated InitScanner: `scan_files/2`, `walk_tree/3`, `walk_entry/4` pass classify_opts through
- 16 new tests: 10 in file_classifier_test, 6 in config_test (+ 1 updated defaults test)
- Test count: 1326 tests + 16 properties, 0 failures

### File List

**Modified:**
- familiar/lib/familiar/config.ex (added indexing field, parsing, validation)
- familiar/lib/familiar/config/generator.ex (added indexing_section/0)
- familiar/lib/familiar/knowledge/file_classifier.ex (configurable via opts)
- familiar/lib/familiar/knowledge/init_scanner.ex (passes indexing config through)
- familiar/test/familiar/knowledge/file_classifier_test.exs (+10 tests)
- familiar/test/familiar/config_test.exs (+7 tests)

### Change Log

- 2026-04-17: Story 9-3 implemented — file classification rules configurable via [indexing] section in config.toml
