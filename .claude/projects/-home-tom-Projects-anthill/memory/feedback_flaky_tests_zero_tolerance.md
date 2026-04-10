---
name: feedback_flaky_tests_zero_tolerance
description: Zero tolerance for flaky tests — hunt them down and fix root causes, never retry or skip
type: feedback
---

Eliminate flaky tests with extreme prejudice. Do not allow them to proliferate.

**Why:** A pre-commit hook failure was masked by a flake that reproduced ~1 in 50 runs, silently hiding real issues. Flaky tests erode trust in the test suite, hide regressions, and train developers to retry instead of investigate. A test that passes "usually" is worse than no test because it asserts false safety.

**How to apply:**

- When a test fails intermittently — even once — treat it as a P1 bug. Stop feature work until it's root-caused.
- Never "retry until green." Never mark a test `@tag :skip` to unblock. Never add `Process.sleep/1` loops hoping the flake goes away.
- Stress-test aggressively: `for i in $(seq 1 50); do mix test --seed $((RANDOM)); done`. If a fix doesn't survive 50 consecutive runs, it isn't a fix.
- Common flake patterns observed in this codebase, documented in past fixes:
  1. **`capture_log` + `assert log == ""`** — `capture_log` collects messages from the whole BEAM including background processes. Assert on *content* (`refute log =~ "specific phrase"`), never on emptiness.
  2. **Fire-and-forget `Task.Supervisor.start_child`** called from code under test — the Task outlives the test process, leaking Mox expectations and holding stale `Ecto.Sandbox` connections. Add a config flag so tests can disable the background work. See `:familiar, :knowledge_background_maintenance` in `config/test.exs`.
  3. **`Process.sleep(N)` as a sync point** — deterministic only when the system is idle. Under full-suite load, `N` ms is never enough. Sync via `GenServer.call/2` (shares the mailbox with sends in FIFO order — NOT `:sys.get_state/1`, which is delivered as a system message and can be processed out-of-order) or `assert_receive`.
  4. **Millisecond-resolution time comparisons with strict `>`** — when code paths can execute within the same millisecond tick, `now - init_value > cooldown_ms` fails where `>=` or a `nil` sentinel would succeed. Initialize time-tracked state to `nil` and special-case the first comparison.
  5. **`async: true` + any `Application.put_env`** — global state leaks across concurrently-running test modules. If you must mutate app env, mark the module `async: false`.
- When reviewing a PR, if you see any of the above patterns, flag them before merge regardless of whether they're currently passing.
- Fix the ROOT CAUSE, never the symptom. A test that fails once in 50 runs has a defect in the code under test, the test itself, or both. Diagnose; don't paper over.
