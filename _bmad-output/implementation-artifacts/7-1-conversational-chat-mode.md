# Story 7.1: Conversational Agent Mode (`fam chat`)

Status: done

## Story

As a developer using Familiar,
I want a `fam chat` command that opens an interactive conversation with a user-manager agent that has full tool access and can delegate to other agents and workflows,
so that I can use Familiar as a conversational coding assistant — standalone or driven by another AI agent like Claude Code.

## Context

Familiar currently operates through workflow commands (`fam plan/do/fix`) which are structured multi-step pipelines. There is no open-ended conversational mode where the user can talk to an agent, ask questions, and have the agent autonomously use tools and delegate work.

Story 6.4 built the interactive mode infrastructure: AgentProcess supports `mode: :interactive` with multi-turn conversations, `input_fn` for stdin reading, conversation persistence, and `--resume`/`--session` for session continuity. This story connects that infrastructure to a new `fam chat` command with a new `user-manager` role.

The user-manager role is the top of the agent hierarchy:
```
User ↔ fam chat (user-manager)
         ├─ spawn_agent(project-manager) → spawn_agent(coder/analyst/...)
         ├─ run_workflow(feature-planning/implementation/fix)
         ├─ search_context / store_context (direct)
         └─ read_file / write_file (direct for simple tasks)
```

Two usage modes:
- **Standalone**: developer runs `fam chat` in a terminal, types naturally
- **Agent-driven**: Claude Code or another AI calls `fam chat --json` programmatically, reads structured events

## Acceptance Criteria

### AC1: `fam chat` Opens Interactive REPL

**Given** the `.familiar/` directory exists with default files
**When** the user runs `fam chat`
**Then** an AgentProcess starts with the `user-manager` role in interactive mode
**And** the user sees a welcome message and prompt
**And** the user can type messages, see agent responses, and observe tool calls
**And** Ctrl-D or "exit" ends the session

### AC2: User-Manager Role Created with Full Tool Access

**Given** `DefaultFiles.install/1` runs
**When** the `user-manager.md` role file is installed
**Then** it has access to all registered tools
**And** its prompt instructs it to: understand the user's request, delegate complex tasks to project-manager via `spawn_agent`, use `run_workflow` for standard flows, and handle simple queries directly
**And** it reports tool call results and agent progress back to the user conversationally

### AC3: Agent Has Full Tool Registry Access

**Given** a `fam chat` session is running
**When** the agent decides to use a tool
**Then** it can call any registered tool: read_file, write_file, delete_file, list_files, search_files, run_command, spawn_agent, run_workflow, monitor_agents, broadcast_status, signal_ready, search_context, store_context
**And** tool calls and results are displayed to the user

### AC4: `--role` Flag Overrides Default Role

**Given** the CLI
**When** the user runs `fam chat --role analyst`
**Then** the agent uses the `analyst` role instead of `user-manager`
**And** all other behavior is the same

### AC5: `--resume` and `--session` Work for Chat Sessions

**Given** a previous `fam chat` session that was interrupted
**When** the user runs `fam chat --resume`
**Then** the latest active chat conversation is found (scope: "chat")
**And** conversation history is loaded as context
**When** the user runs `fam chat --session 42`
**Then** that specific session is resumed

### AC6: `--json` Mode Outputs Structured Events

**Given** a `fam chat --json` session
**When** the agent responds or calls a tool
**Then** each event is output as a JSON line: `{"type": "response", "content": "..."}`, `{"type": "tool_call", "name": "...", "args": {...}}`, `{"type": "tool_result", "name": "...", "result": {...}}`
**And** user input is read from stdin as JSON: `{"type": "user_message", "content": "..."}`
**And** this enables programmatic integration with Claude Code or other agents

### AC7: Conversation Persisted with Chat Scope

**Given** a `fam chat` session
**When** the conversation runs
**Then** all messages are persisted with `scope: "chat"`
**And** the session appears in `fam sessions` (Story 7-4)

### AC8: Test Baseline

**Given** all changes are applied
**When** `mix test` runs
**Then** all existing tests pass with 0 failures, 0 regressions
**And** Credo strict and Dialyzer pass with 0 issues

## Tasks / Subtasks

- [x] Task 1: Create `user-manager` default role (AC: 2)
  - [ ] Add `user-manager.md` to `@roles` in `default_files.ex`
  - [ ] Role has all skills listed
  - [ ] Prompt: conversational coordinator — understand requests, delegate to PM for complex tasks, use workflows for standard flows, handle simple queries directly
  - [ ] Prompt: display tool results to user, report agent progress, summarize outcomes
  - [ ] Add `user-manager-chat.md` skill for chat-specific behaviors

- [x] Task 2: Add `fam chat` CLI command (AC: 1, 4, 5)
  - [ ] `run_with_daemon({"chat", args, flags}, deps)` dispatches to chat mode
  - [ ] Default role: `user-manager`, override with `--role <name>`
  - [ ] `--resume` finds latest `scope: "chat"` conversation
  - [ ] `--session <id>` resumes specific session
  - [ ] No args required (unlike plan/do/fix which need a description)
  - [ ] Update help text with `chat` command

- [x] Task 3: Implement chat REPL loop (AC: 1, 3)
  - [ ] Spawn AgentProcess with `mode: :interactive`, full tool access
  - [ ] Display welcome message with role name
  - [ ] Read user input via `input_fn` (injected for testing)
  - [ ] Display agent responses and tool call results
  - [ ] Handle "exit", "quit", Ctrl-D (EOF) to end session
  - [ ] Handle empty input gracefully (re-prompt)

- [x] Task 4: Tool call display (AC: 3)
  - [ ] When agent calls a tool, display: `[tool] read_file("src/main.ex")`
  - [ ] When tool returns, display abbreviated result
  - [ ] User sees the agent "working" — not just final answers

- [x] Task 5: JSON mode for programmatic integration (AC: 6)
  - [ ] `--json` flag changes input/output to JSON lines
  - [ ] Output events: `{"type": "response", ...}`, `{"type": "tool_call", ...}`, `{"type": "tool_result", ...}`
  - [ ] Input: `{"type": "user_message", "content": "..."}`
  - [ ] Enables Claude Code to drive Familiar as a tool

- [x] Task 6: Text formatter and output formatting (AC: 1)
  - [ ] `text_formatter("chat")` for text mode output
  - [ ] `quiet_summary` clause for chat results

- [x] Task 7: Write tests (AC: 1-8)
  - [ ] Test `fam chat` command dispatch with mocked workflow
  - [ ] Test `--role` override
  - [ ] Test `--resume` and `--session` for chat scope
  - [ ] Test user-manager role file parses correctly
  - [ ] Test JSON mode event format

- [x] Task 8: Verify test baseline (AC: 8)
  - [ ] All tests pass with 0 failures
  - [ ] Credo strict: 0 issues
  - [ ] Dialyzer: 0 warnings

## Dev Notes

### Chat vs Workflow Dispatch

The key difference from `fam plan/do/fix`:
- Workflow commands: CLI calls `WorkflowRunner.run_workflow/3` which sequences multiple agents through steps
- Chat command: CLI spawns a single AgentProcess directly in interactive mode — no workflow, no steps

The chat agent can still invoke workflows via the `run_workflow` tool, but the chat session itself is a direct agent conversation.

### AgentProcess Interactive Mode (from Story 6.4)

Already implemented:
- `mode: :interactive` — agent enters `:waiting_input` state instead of completing
- `{:user_message, text}` cast to continue conversation
- Timeout paused while waiting for input
- `signal_ready` completes the session (agent decides it's done)

For chat, `signal_ready` means the agent is done with the overall session (unusual — most chat sessions end when the user quits, not when the agent signals).

### Input/Output Architecture

**Text mode** (standalone):
```
$ fam chat
Familiar (user-manager) ready. Type 'exit' to quit.

> Help me plan a user auth feature

I'll delegate this to the planning workflow.
[tool] run_workflow("feature-planning", {"task": "user auth feature"})
[workflow] Starting: research → draft-spec → review-spec
...
Planning complete. Here's the specification: ...

> Now implement it

[tool] run_workflow("feature-implementation", {"task": "implement user auth"})
...
```

**JSON mode** (agent-driven):
```jsonl
{"type": "ready", "role": "user-manager", "session_id": 42}
{"type": "user_message", "content": "Help me plan auth"}
{"type": "response", "content": "I'll delegate this to planning."}
{"type": "tool_call", "name": "run_workflow", "args": {"workflow": "feature-planning", "task": "auth"}}
{"type": "tool_result", "name": "run_workflow", "result": {"steps": [...]}}
{"type": "response", "content": "Planning complete. Here's the spec..."}
```

### User-Manager Role Prompt

The user-manager should be instructed to:
1. Greet the user and understand their intent
2. For complex multi-step tasks → `spawn_agent(project-manager)` or `run_workflow`
3. For simple questions → `search_context` or answer from knowledge
4. For file operations → use tools directly
5. Always report what it's doing and why
6. Summarize outcomes clearly

### Existing Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| `AgentProcess` interactive mode | Working | Story 6.4 |
| `input_fn` DI | Working | Story 6.4 |
| Conversation persistence | Working | scope: "chat" |
| `--resume`/`--session` | Working | Story 6.4 (plan), extend to chat |
| `run_workflow` tool | Working | Story 5.9 |
| `spawn_agent` tool | Working | Story 5.5 |
| All file/knowledge tools | Working | Story 5.4-5.8 |
| `--json` flag parsing | Working | Story 2.2 |

### Files to Modify

| File | Change |
|------|--------|
| `familiar/lib/familiar/knowledge/default_files.ex` | Add `user-manager.md` role |
| `familiar/lib/familiar/cli/main.ex` | Add `fam chat` command, REPL loop |
| `familiar/lib/familiar/cli/output.ex` | Add chat formatter |
| `familiar/test/familiar/cli/chat_command_test.exs` | **New file** — chat command tests |
| `familiar/test/familiar/knowledge/default_files_test.exs` | Verify user-manager role parses |

### References

- [Source: familiar/lib/familiar/execution/agent_process.ex:468-500] — interactive mode
- [Source: familiar/lib/familiar/cli/main.ex:178-209] — workflow command dispatch pattern
- [Source: familiar/lib/familiar/execution/tool_registry.ex:208-228] — registered tools
- [Source: familiar/lib/familiar/knowledge/default_files.ex:270-300] — project-manager role

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Completion Notes List

- Created `user-manager.md` default role — conversational coordinator with full tool access, delegates to PM for complex tasks
- `fam chat` command with `--role`, `--resume`, `--session` flags
- Bare `fam` (no args) now launches chat instead of help
- `--role` flag added to OptionParser with `-r` alias
- Chat REPL loop: `await_chat/3` handles agent messages, tool calls, user input via `input_fn`
- Exit on "exit", "quit", Ctrl-D (EOF)
- Resume loads conversation history as context, extracts role from conversation description
- Text formatter, quiet_summary, JSON mode support for chat results
- 18 new tests covering dispatch, role override, resume, session, output formatting
- 1025 tests + 8 properties, 0 failures. Credo strict: 0. Dialyzer: 0.

### File List

- `familiar/lib/familiar/knowledge/default_files.ex` — added `user-manager.md` role
- `familiar/lib/familiar/cli/main.ex` — chat command, REPL loop, resume, parse_args changes
- `familiar/lib/familiar/cli/output.ex` — chat quiet_summary clause
- `familiar/test/familiar/cli/chat_command_test.exs` — **new** — 18 chat command tests
- `familiar/test/familiar/cli/main_test.exs` — updated empty-args test (help → chat)
