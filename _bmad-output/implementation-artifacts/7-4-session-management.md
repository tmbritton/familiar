# Story 7.4: Session Management Commands

Status: done

## Story

As a developer using the `fam` CLI,
I want `fam sessions` to list, inspect, and clean up conversation sessions,
so that I can see what agent sessions exist, review their history, and remove stale ones.

## Context

Stories 7-1 (chat) and 6-4 (plan --resume) created conversations with `scope: "chat"` and `scope: "planning"`. These persist in SQLite but there's no way to list or manage them from the CLI. The `Conversations` module has `create`, `get`, `latest_active`, `messages`, and `update_status` — but no list/query function.

## Acceptance Criteria

### AC1: `fam sessions` Lists All Sessions

**Given** conversations exist in the database
**When** the user runs `fam sessions`
**Then** all conversations are listed with ID, scope, status, description (truncated), message count, and timestamp
**And** sorted by most recent first

### AC2: `fam sessions <id>` Shows Session Details

**Given** a conversation ID
**When** the user runs `fam sessions 42`
**Then** the session details are shown: ID, scope, status, description, created/updated timestamps
**And** the message count and last few messages (role + content preview) are displayed

### AC3: `fam sessions --scope <scope>` Filters by Scope

**Given** conversations with different scopes (chat, planning, agent)
**When** the user runs `fam sessions --scope chat`
**Then** only conversations with scope "chat" are shown

### AC4: `fam sessions --cleanup` Closes Stale Sessions

**Given** conversations with status "active" that are older than a threshold
**When** the user runs `fam sessions --cleanup`
**Then** stale active sessions are marked as "abandoned"
**And** the count of cleaned up sessions is reported

### AC5: JSON and Quiet Output Modes

**Given** any sessions command
**When** run with `--json` or `--quiet`
**Then** output uses the standard format

### AC6: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict and Dialyzer pass with 0 issues

## Tasks / Subtasks

- [ ] Task 1: Add `list/1` to Conversations module (AC: 1, 3)
  - [ ] `list(opts)` — query conversations with optional scope/status filters
  - [ ] Order by `inserted_at` desc (most recent first)
  - [ ] Include message count via subquery or preload
  - [ ] Return `{:ok, [%{conversation, message_count}]}`

- [ ] Task 2: Add `cleanup_stale/1` to Conversations module (AC: 4)
  - [ ] Find active conversations older than threshold (default 24 hours)
  - [ ] Update status to "abandoned"
  - [ ] Return `{:ok, %{cleaned: count}}`

- [ ] Task 3: Add `fam sessions` CLI commands (AC: 1-4)
  - [ ] `run_with_daemon({"sessions", [], flags}, deps)` — list sessions
  - [ ] `run_with_daemon({"sessions", [id], _}, deps)` — show session detail
  - [ ] `--scope` flag filters by scope
  - [ ] `--cleanup` flag triggers stale session cleanup
  - [ ] DI via `list_sessions_fn`, `get_session_fn`, `cleanup_fn` in deps
  - [ ] Add `--scope` to OptionParser strict list

- [ ] Task 4: Add text formatters and quiet_summary (AC: 5)
  - [ ] `text_formatter("sessions")` — table format for list, detail view for single
  - [ ] `quiet_summary` clauses

- [ ] Task 5: Update help text

- [ ] Task 6: Write tests (AC: 1-6)
  - [ ] Test Conversations.list with scope filter
  - [ ] Test Conversations.cleanup_stale
  - [ ] Test CLI dispatch for list, detail, scope filter, cleanup
  - [ ] Test JSON and quiet output

- [ ] Task 7: Verify test baseline (AC: 6)

## Dev Notes

### Conversations.list/1

```elixir
def list(opts \\ []) do
  scope = Keyword.get(opts, :scope)
  status = Keyword.get(opts, :status)

  query = from(c in Conversation, order_by: [desc: c.inserted_at])
  query = if scope, do: where(query, [c], c.scope == ^scope), else: query
  query = if status, do: where(query, [c], c.status == ^status), else: query

  conversations = Repo.all(query)
  {:ok, conversations}
end
```

### Output Format

**`fam sessions` (text):**
```
Sessions (5):
  ID   Scope      Status     Description                    Messages  Updated
  42   chat       active     user-manager: Interactive...   12        2 min ago
  41   planning   completed  analyst: Plan auth feature     8         1 hour ago
  40   agent      completed  coder: Implement login         6         3 hours ago
```

**`fam sessions 42` (text):**
```
Session #42
  Scope: chat
  Status: active
  Description: user-manager: Interactive chat session
  Created: 2026-04-06 15:30:00Z
  Messages: 12

  Recent messages:
    [user] Help me refactor the auth module
    [assistant] I'll analyze the current structure...
    [tool] read_file("lib/auth.ex") → 150 lines
    [assistant] The auth module has 3 main functions...
```

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/conversations/conversations.ex` | Add `list/1`, `cleanup_stale/1` |
| `familiar/lib/familiar/cli/main.ex` | Sessions commands, formatters, help, --scope flag |
| `familiar/lib/familiar/cli/output.ex` | quiet_summary |
| `familiar/test/familiar/cli/sessions_test.exs` | **New file** — CLI tests |
| `familiar/test/familiar/conversations/conversations_test.exs` | Tests for list/cleanup |

### References

- [Source: familiar/lib/familiar/conversations/conversations.ex] — current API
- [Source: familiar/lib/familiar/conversations/conversation.ex] — schema
- [Source: familiar/lib/familiar/cli/main.ex:369-449] — roles/skills pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Added `Conversations.list/1` with scope/status filters, `message_count/1`, `cleanup_stale/1`
- `fam sessions` lists all sessions with ID, scope, status, description
- `fam sessions <id>` shows details with recent messages
- `fam sessions --scope chat` filters by scope
- `fam sessions --cleanup` marks stale active sessions as abandoned
- Added `--scope` and `--cleanup` to OptionParser
- Text formatter with table layout, quiet_summary, JSON support
- 14 new tests (3 Conversations module + 7 CLI + 4 output), 1062 total, 0 failures
- Credo: 0. Dialyzer: 0.

### File List

- `familiar/lib/familiar/conversations/conversations.ex` — added list/1, message_count/1, cleanup_stale/1
- `familiar/lib/familiar/cli/main.ex` — sessions commands, formatter, help, --scope/--cleanup flags
- `familiar/lib/familiar/cli/output.ex` — quiet_summary clauses
- `familiar/test/familiar/cli/sessions_test.exs` — **new** — 14 tests
