# Epic 5.5 Retrospective: Async Tool Dispatch & Concurrency Hardening

Date: 2026-04-04

## Epic Summary

- **Epic:** 5.5 — Async Tool Dispatch & Concurrency Hardening
- **Stories:** 3/3 completed (100%) + 1 deferred-items cleanup commit
- **Action Items from Epic 5 Retro:** 4 identified, all 4 addressed
- **Tests:** 955 → 965 (+10 tests)
- **Test suite time:** 15s → 7s (53% faster)
- **Credo strict:** 0 issues throughout
- **Review patches applied:** 9 across 3 reviews
- **Deferred items resolved:** 5 (from review findings)
- **Deferred to post-MVP:** 8 (edge cases, architectural)

## Epic 5 Retro Follow-Through

| Status | Item | Notes |
|--------|------|-------|
| ✅ | Async tool dispatch via GenServer.reply/2 | Story 5.5.1 — ~9x speedup in benchmark |
| ✅ | File-level claim checking before write | Story 5.5.2 — check_claim/2 + clear_stale_transaction |
| ✅ | Hooks mailbox back-pressure | Story 5.5.3 — event handler timeouts + mailbox depth warning |
| ✅ | Benchmark tool dispatch latency | Done in Story 5.5.1 benchmark test |

**Verdict:** All 4 action items from Epic 5 retro addressed. Clean slate entering Phase 3.

## Successes

1. **Test suite speedup was a force multiplier.** Reducing suite time from 15s to 7s made the entire epic faster. The fix was simple DI: configurable timeouts in test env instead of hardcoded production values. This should have been done from Epic 5 Story 5.1.

2. **Small, focused stories kept scope tight.** Each story touched 2-3 files. Code reviews were fast and findings were concrete. No story required architectural debate — the patterns were established in Epic 5.

3. **Review findings drove real improvements.** Story 5.5.1 review caught the `start_child` failure path (caller hangs forever) and reply ordering (broadcast before reply). Story 5.5.2 review uncovered the same-task re-write bug — agents couldn't revise files within a single task. These would have been production bugs.

4. **Deferred items cleanup pass was efficient.** Batching 5 quick fixes into one commit avoided 5 separate story cycles while still addressing real gaps.

## Challenges

1. **Monotonic time can be negative.** `System.monotonic_time(:millisecond)` on BEAM returns a value relative to an arbitrary epoch — often a large negative number. Initializing `last_mailbox_warning: 0` and using `abs(now - 0)` was a workaround that the review correctly flagged. Fix: initialize to `monotonic_time() - cooldown`.

2. **`capture_log` doesn't capture from GenServer processes reliably.** The Erlang logger is async by default — logs from other processes may not flush before `capture_log` returns. Pattern: always add `Logger.flush()` inside `capture_log` blocks that assert on logs from GenServers.

3. **Global Hooks pollution in tests.** Story 5.5.1 initially registered a veto hook on the global Hooks server. This caused a flaky failure. Fix: never register hooks on the global server in async tests.

4. **`Task.Supervisor.start_child` raises instead of returning error.** When the supervisor is dead, `start_child` raises `** (EXIT) no process` instead of `{:error, _}`. Requires `catch :exit, reason` alongside the `case` pattern match.

## Key Insights

1. **DI for timeouts is a testing pattern, not just a convenience.** Every hardcoded timeout is a test suite tax. Future modules should make all timeouts configurable from day one.

2. **The deferred items pattern works well.** Classify during review (patch/defer/dismiss), fix patches immediately, batch-resolve actionable defers at epic end. Nothing falls through the cracks.

3. **SQLite single-writer provides implicit concurrency safety.** The TOCTOU race in `check_claim` is theoretically real but practically impossible — queries serialize at the database level.

## Metrics

| Metric | Value |
|--------|-------|
| Stories completed | 3 + 1 cleanup commit |
| Tests added | +10 |
| Test suite speedup | 15s → 7s (53%) |
| Review patches | 9 |
| Deferred resolved | 5 |
| Deferred to post-MVP | 8 (edge cases) |
| Regressions | 0 |
| Credo issues | 0 |

## Patterns Established

1. **Configurable timeouts via app env** — `Application.get_env(:familiar, Module, [])[:key]` with module attribute defaults
2. **`GenServer.reply/2` for async dispatch** — lookup + hooks in handle_call, execution in spawned Task
3. **Wrapper task for event handler timeout** — outer task monitors inner with yield/shutdown
4. **`catch :exit` alongside `rescue`** — for OTP calls that raise exits
5. **`Logger.flush()` in `capture_log` blocks** — when asserting logs from GenServer processes
6. **`:sys.suspend`/`:sys.resume` for mailbox testing** — queue messages while GenServer is suspended
7. **`clear_stale_transaction` before insert** — enables same-task file revision

## Preparation for Phase 3

Epic 5.5 was the bridge. The harness now has:
- Non-blocking tool dispatch (concurrent agents don't serialize)
- File-level claim protection (concurrent agents can't overwrite each other)
- Event handler back-pressure (hooks don't flood under load)
- Agent crash cleanup (terminate rolls back file claims)

Phase 3 prerequisites met. Epic 6 (Default Workflows & CLI) can proceed.
