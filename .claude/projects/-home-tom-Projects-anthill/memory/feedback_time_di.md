---
name: DI for Time-Dependent Tests
description: When tests depend on wall clock time, inject the Clock behaviour instead of using far-future dates or sleep. Learned in Epic 2 Story 2.7.
type: feedback
---

When tests depend on wall clock time, that's the signal to inject the clock, not to pick clever dates or add sleep/wait times.

**Why:** In Story 2.7, freshness tests passed or failed depending on what time of day they ran because `entry.updated_at` used the real system clock. The far-future date hack was fragile. Buddy explicitly asked for DI instead.

**How to apply:** Any time a test compares timestamps or depends on "now", ensure the time source is injectable via the Clock behaviour port. Use `autogenerate` delegation for Ecto schemas. Stub ClockMock in DataCase setup so all tests get a working clock by default.
