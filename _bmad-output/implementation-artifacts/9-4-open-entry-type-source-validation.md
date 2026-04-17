# Story 9-4: Open Entry Type and Source Validation

Status: review

## Story

As a Familiar user in a non-coding domain,
I want to store knowledge entries with custom types like "experiment", "runbook", or "finding",
So that the knowledge store adapts to my domain rather than forcing software engineering categories.

## Acceptance Criteria

1. **AC1: Format validation replaces allowlist.** `Entry.changeset/2` validates `:type` and `:source` with a format rule (`~r/^[a-z][a-z0-9_]*$/`, 1–50 chars) instead of `validate_inclusion` against `@valid_types`/`@valid_sources`. All existing types and sources still pass. Custom types like `"experiment"`, `"runbook"`, `"finding"` now also pass.

2. **AC2: Default types/sources exposed.** Module attributes renamed to `@default_types` and `@default_sources`. Public functions `Entry.default_types/0` and `Entry.default_sources/0` expose them. Old `valid_types/0` and `valid_sources/0` removed or aliased.

3. **AC3: Hygiene updated.** `Hygiene` module's `@valid_hygiene_types` replaced with format validation matching AC1's regex. `valid_hygiene_entry?/1` accepts any snake_case type string, not just the hardcoded 5.

4. **AC4: Extractor updated.** `Extractor.build_prompt/2` reads from `Entry.default_types/0` instead of hardcoding `"file_summary", "convention", ...`. `valid_entry?/1` uses the same format validation as AC1 (any snake_case type passes).

5. **AC5: Entry tests.** `entry_test.exs` updated: custom types (`"experiment"`, `"runbook"`) succeed. Invalid formats (`""`, `"Has Spaces"`, `"123start"`, strings > 50 chars) fail. All existing tests adapted to new validation.

6. **AC6: Extractor tests.** `extractor_test.exs` — `valid_entry?` test (if any) updated. `build_prompt/2` test verifies prompt includes types from `Entry.default_types/0`.

7. **AC7: Hygiene tests.** `hygiene_test.exs` — verify custom types from LLM responses are accepted (not filtered out by `valid_hygiene_entry?`).

8. **AC8: Clean toolchain.** `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`, `mix dialyzer` all pass.

9. **AC9: Stress-tested.** `entry_test.exs`, `extractor_test.exs`, and `hygiene_test.exs` pass 50 consecutive runs with no flakes.

## Tasks / Subtasks

- [x] Task 1: Update Entry module — format validation (AC: 1, 2)
  - [x] Rename `@valid_types` → `@default_types`, `@valid_sources` → `@default_sources`
  - [x] Add `@slug_format ~r/^[a-z][a-z0-9_]*$/` module attribute
  - [x] Replace `validate_inclusion(:type, @valid_types)` with `validate_format(:type, @slug_format)` + `validate_length(:type, min: 1, max: 50)`
  - [x] Same for `:source` validation
  - [x] Rename `valid_types/0` → `default_types/0`, `valid_sources/0` → `default_sources/0`

- [x] Task 2: Update Hygiene module (AC: 3)
  - [x] Remove `@valid_hygiene_types` module attribute
  - [x] Add `@slug_format ~r/^[a-z][a-z0-9_]*$/` module attribute
  - [x] Update `valid_hygiene_entry?/1` to use format validation: `Regex.match?(@slug_format, type)` instead of `type in @valid_hygiene_types`

- [x] Task 3: Update Extractor module (AC: 4)
  - [x] In `build_prompt/2`: replace hardcoded type list with `Entry.default_types()` interpolation
  - [x] Add `@slug_format ~r/^[a-z][a-z0-9_]*$/` module attribute
  - [x] Update `valid_entry?/1` to use format regex instead of `type in ~w(file_summary convention ...)`

- [x] Task 4: Update entry_test.exs (AC: 5)
  - [x] Remove "invalid with unknown type" and "invalid with unknown source" tests (custom types now valid)
  - [x] Update "accepts all valid types" → "accepts all default types", use `default_types/0`
  - [x] Update "accepts all valid sources" → "accepts all default sources", use `default_sources/0`
  - [x] Add: custom type `"experiment"` succeeds
  - [x] Add: custom type `"runbook"` succeeds
  - [x] Add: custom source `"webhook"` succeeds
  - [x] Add: empty type `""` fails
  - [x] Add: `"Has Spaces"` fails
  - [x] Add: `"123start"` fails (must start with lowercase letter)
  - [x] Add: 51-char type string fails
  - [x] Add: `"valid_snake_case_type"` succeeds
  - [x] Add: empty source `""` fails
  - [x] Add: uppercase source `"InitScan"` fails
  - [x] Add: `default_types/0` and `default_sources/0` tests

- [x] Task 5: Update extractor_test.exs (AC: 6)
  - [x] Add test: `build_prompt/2` output includes default types from `Entry.default_types/0`
  - [x] Update "filters out entries with invalid types" → test invalid format (`"Has Spaces"`) instead of `"invalid_type"`
  - [x] Add test: custom snake_case type `"experiment"` accepted from LLM

- [x] Task 6: Update hygiene_test.exs (AC: 7)
  - [x] Add test: LLM response with custom type `"insight"` is accepted
  - [x] Update "filters out invalid types like file_summary" → test invalid format (`"Has Spaces"`) instead

- [x] Task 7: Toolchain verification (AC: 8)
  - [x] `mix compile --warnings-as-errors` — clean
  - [x] `mix format --check-formatted` — clean
  - [x] `mix credo --strict` — 0 issues
  - [x] `mix test` — 1342 tests + 16 properties, 0 failures
  - [x] `mix dialyzer` — 0 errors

- [x] Task 8: Stress-test (AC: 9)
  - [x] 50x run on `entry_test.exs` — 51/51 clean
  - [x] 50x run on `extractor_test.exs` — 51/51 clean
  - [x] 50x run on `hygiene_test.exs` — 51/51 clean

## Dev Notes

### Current Entry validation (entry.ex lines 14-15, 39-40)

```elixir
@valid_types ~w(convention file_summary architecture relationship decision fact gotcha)
@valid_sources ~w(init_scan post_task manual agent user)

# In changeset/2:
|> validate_inclusion(:type, @valid_types)
|> validate_inclusion(:source, @valid_sources)
```

Replace with format + length validation. The regex `~r/^[a-z][a-z0-9_]*$/` ensures:
- Starts with lowercase letter
- Contains only lowercase letters, digits, underscores
- At least 1 character (enforced by regex `+` quantifier)
- Max 50 chars (enforced by `validate_length`)

### Current Hygiene validation (hygiene.ex line 23, 209-211)

```elixir
@valid_hygiene_types ~w(fact decision gotcha relationship convention)

defp valid_hygiene_entry?(%{"type" => type, "text" => text})
     when is_binary(type) and is_binary(text) do
  type in @valid_hygiene_types and String.trim(text) != ""
end
```

Change to regex match instead of `in` check. Keep the `String.trim(text) != ""` guard.

### Current Extractor validation (extractor.ex lines 76, 121-125)

```elixir
# In build_prompt/2:
Valid types: "file_summary", "convention", "architecture", "relationship", "decision"

# In valid_entry?/1:
type in ~w(file_summary convention architecture relationship decision)
```

Two changes needed:
1. `build_prompt/2`: interpolate `Entry.default_types/0` so types stay in sync
2. `valid_entry?/1`: use format regex (same as Entry and Hygiene)

### Callers of valid_types/0 and valid_sources/0

Search for `Entry.valid_types` and `Entry.valid_sources` to find all callers. The rename to `default_types/0`/`default_sources/0` must update all call sites. Known callers:
- `entry_test.exs` line 59: `Entry.valid_types()`
- `entry_test.exs` line 66: `Entry.valid_sources()`

### What NOT to touch

- **Schema or migrations** — SQLite column is already a plain string, no changes needed
- **Knowledge module** (`knowledge.ex`) — stores entries via changeset, will work automatically
- **SecretFilter** — not related to type validation
- **Config or FileClassifier** — separate concerns (Story 9-3)

### Previous story patterns (Story 9-3)

- Code review caught missing validation for `test_patterns` — similar pattern here: verify all validation paths are exhaustive
- Credo nesting depth issues — keep validation helpers flat
- 50x stress testing on all touched test files
- Full toolchain check including dialyzer

### Project Structure Notes

- Entry: `lib/familiar/knowledge/entry.ex` (59 lines)
- Hygiene: `lib/familiar/knowledge/hygiene.ex` (295 lines)
- Extractor: `lib/familiar/knowledge/extractor.ex` (132 lines)
- Entry test: `test/familiar/knowledge/entry_test.exs` (99 lines)
- Extractor test: `test/familiar/knowledge/extractor_test.exs`
- Hygiene test: `test/familiar/knowledge/hygiene_test.exs`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 9-4] — Epic scope definition
- [Source: familiar/lib/familiar/knowledge/entry.ex:14-15,39-40] — Current type/source validation
- [Source: familiar/lib/familiar/knowledge/hygiene.ex:23,209-211] — Current hygiene type allowlist
- [Source: familiar/lib/familiar/knowledge/extractor.ex:71-93,121-125] — Current extractor prompt and type allowlist
- [Source: _bmad-output/implementation-artifacts/9-3-configurable-file-classification.md] — Previous story patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Two additional test files needed updating beyond story scope: `embedding_pipeline_test.exs` and `knowledge_store_test.exs` — both had tests expecting `"invalid_type"` to fail validation, but that's now a valid snake_case format. Changed to `"Has Spaces"`.
- `mix format` auto-corrected line wrapping in `entry.ex` changeset pipeline (long `validate_format` line).
- Credo flagged `Familiar.Knowledge.Entry` nested module reference in `extractor_test.exs` — added alias.

### Completion Notes List

- Renamed `@valid_types`/`@valid_sources` → `@default_types`/`@default_sources` in Entry
- Added `@slug_format ~r/^[a-z][a-z0-9_]*$/` shared across Entry, Hygiene, and Extractor
- Replaced `validate_inclusion` with `validate_format` + `validate_length` in Entry changeset
- Replaced `@valid_hygiene_types` allowlist with regex match in Hygiene
- Extractor `build_prompt/2` now reads types from `Entry.default_types/0`
- Extractor `valid_entry?/1` uses format regex instead of hardcoded type list
- 21 entry tests (was 10), 14 extractor tests (was 12), 28 hygiene tests (was 27)
- Test count: 1342 tests + 16 properties, 0 failures

### File List

**Modified:**
- familiar/lib/familiar/knowledge/entry.ex (format validation, renamed attrs/functions)
- familiar/lib/familiar/knowledge/hygiene.ex (format validation replaces allowlist)
- familiar/lib/familiar/knowledge/extractor.ex (dynamic types in prompt, format validation)
- familiar/test/familiar/knowledge/entry_test.exs (rewritten for format validation)
- familiar/test/familiar/knowledge/extractor_test.exs (+2 tests, updated 1)
- familiar/test/familiar/knowledge/hygiene_test.exs (+1 test, updated 1)
- familiar/test/familiar/knowledge/embedding_pipeline_test.exs (updated invalid type test)
- familiar/test/familiar/extensions/knowledge_store_test.exs (updated invalid type test)

### Change Log

- 2026-04-17: Story 9-4 implemented — entry type/source validation relaxed from allowlist to format validation
