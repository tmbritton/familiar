# Familiar

A multi-agent harness that builds institutional memory about your codebase. Familiar runs LLM-powered agents that plan features, implement code, review changes, and accumulate project knowledge — all from the command line.

**Security warning:** Familiar executes LLM-generated tool calls including file writes and shell commands. The LLM is an untrusted actor. **Run Familiar inside a container.** See [Sandboxing](#sandboxing) below.

## What it does

- **Agents as markdown.** Roles, skills, and workflows are plain markdown files in `.familiar/`. Edit them, add new ones, check them into version control. No Elixir code required to change agent behavior.
- **Knowledge store.** Familiar scans your project on init, extracts conventions and patterns via the LLM, and stores them as vector-embedded entries in a local SQLite database. Agents query this store for context before acting.
- **Multi-step workflows.** `fam plan "add user auth"` runs a three-step workflow (research, draft-spec, review). `fam do "implement login"` runs implement, test, review. `fam fix "flaky timeout"` runs diagnose, fix, verify. Workflows are resumable across sessions.
- **CLI-first with JSON output.** Every command supports `--json` for machine-readable output. Third-party agents (Claude Code, Cursor, etc.) can drive Familiar programmatically.
- **Bring your own LLM.** Works with any OpenAI-compatible API (OpenRouter, DeepSeek, Together AI, Groq, local Ollama). Configure in `.familiar/config.toml` with `${ENV_VAR}` interpolation for secrets.

## Quick start

### Prerequisites

- Erlang/OTP 26+ and Elixir 1.15+
- An OpenAI-compatible LLM provider (API key + base URL)

### Install

```bash
git clone <repo-url> familiar
cd familiar
mix deps.get
ln -s "$(pwd)/bin/fam" ~/.local/bin/fam
```

### Initialize a project

```bash
cd ~/your-project
export FAMILIAR_API_KEY=sk-...
export FAMILIAR_BASE_URL=https://openrouter.ai/api/v1
export FAMILIAR_CHAT_MODEL=deepseek/deepseek-chat-v3-0324
export FAMILIAR_PROVIDER=openai_compatible
fam init
```

Familiar creates a `.familiar/` directory with default roles, skills, workflows, and a `config.toml`. It scans your project and builds an initial knowledge store.

### Use it

```bash
fam chat                        # Interactive conversation with full tool access
fam plan "add user auth"        # Plan a feature (research -> draft-spec -> review)
fam do "implement login page"   # Implement (implement -> test -> review)
fam fix "timeout in worker"     # Fix a bug (diagnose -> fix -> verify)
```

`fam` works from any subdirectory of your project (like `git`). Run `fam where` to see how the project directory was resolved.

## Commands

```
fam chat [--role <name>]        Interactive conversation (default command)
fam plan <description>          Plan a feature
fam do <description>            Implement a feature
fam fix <description>           Fix a bug

fam roles [<name>]              List or inspect agent roles
fam skills [<name>]             List or inspect skills
fam workflows [<name>]          List or inspect workflows
fam workflows resume [--id <n>] Resume an interrupted workflow run
fam extensions                  List loaded extensions and their tools
fam sessions [<id>]             List or inspect conversation sessions
fam validate [roles|skills|workflows]  Validate configuration files

fam search <query>              Search knowledge store (curated by Librarian)
fam search --raw <query>        Search without curation
fam entry <id>                  Inspect a knowledge entry
fam context --refresh [path]    Re-scan project or specific path
fam context --reindex           Re-embed all entries with the current model
fam context --compact           Consolidate duplicate entries
fam conventions                 List discovered conventions
fam status                      Knowledge store health and status

fam config                      Show current configuration
fam health                      Check daemon health and version
fam where                       Show resolved project directory and diagnostics
fam version                     Show CLI version
fam daemon start|stop|status    Manage the background daemon
```

All commands support `--json` for machine-readable output and `--quiet` for scripting.

## Configuration

After `fam init`, edit `.familiar/config.toml`:

```toml
[[providers]]
name = "openrouter"
type = "openai_compatible"
default = true
base_url = "${FAMILIAR_BASE_URL}"
api_key = "${FAMILIAR_API_KEY}"
chat_model = "${FAMILIAR_CHAT_MODEL}"
embedding_model = "openai/text-embedding-3-small"
```

Environment variables are interpolated at runtime via `${VAR}` syntax, so secrets never need to be stored in the file.

### Supported providers

Any OpenAI-compatible API works. Tested with:

| Provider | `base_url` | Notes |
|----------|-----------|-------|
| OpenRouter | `https://openrouter.ai/api/v1` | Recommended; access to many models |
| DeepSeek | `https://api.deepseek.com` | Cost-effective |
| Together AI | `https://api.together.xyz/v1` | Fast inference |
| Groq | `https://api.groq.com/openai/v1` | Very fast inference |
| Ollama | `http://localhost:11434/v1` | Local, no API key needed |

### Language detection

Familiar auto-detects your project language on init and configures test/build/lint commands:

Elixir, Go, JavaScript/TypeScript, Python, Rust, Ruby, Java

## Customization

### Roles

Roles are markdown files in `.familiar/roles/`. Each defines an agent's personality, model, lifecycle, skills, and system prompt:

```markdown
---
name: coder
description: Implements features following project conventions
model: sonnet
lifecycle: task
skills:
  - implement
  - test
---
You are an expert software engineer. Follow the project's conventions...
```

### Workflows

Workflows are markdown files in `.familiar/workflows/` that chain multiple agent steps:

```markdown
---
name: feature-implementation
description: Implement an approved feature specification
steps:
  - name: implement
    role: coder
  - name: test
    role: coder
  - name: review
    role: reviewer
---
```

### Skills

Skills are markdown files in `.familiar/skills/` that define focused capabilities agents can reference.

All three are plain text, version-controllable, and editable without touching Elixir code.

## Architecture

Familiar is an Elixir/Phoenix application that runs as a per-project daemon.

- **BEAM/OTP supervision.** Each agent task is a GenServer under a DynamicSupervisor. Crashes are isolated; the harness stays up.
- **SQLite + sqlite-vec.** Knowledge entries with vector embeddings for semantic search. Per-project database at `.familiar/familiar.db`.
- **Hexagonal architecture.** Six Mox-based behaviour ports (LLM, FileSystem, Embedder, Shell, Notifications, Clock) for full testability.
- **Extension system.** `Familiar.Extension` behaviour with lifecycle hooks (`before_tool_call`, `after_tool_call`) and a `ToolRegistry` for dynamic tool registration.
- **CLI as HTTP client.** The `fam` CLI talks to the daemon over HTTP (Req) for simple commands and Phoenix Channels for interactive sessions (streaming responses, tool-call visibility).

## Sandboxing

Familiar has no runtime safety layer. The LLM generates tool calls — including `write_file`, `delete_file`, and `run_command` — and Familiar executes them. A name-pattern-matching "safety" module was removed because it provided false confidence: an adversarial LLM can trivially bypass name-based filters (e.g., calling `sh` instead of `run_command`).

The honest security boundary is the OS. **Run Familiar inside a container:**

```bash
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -e FAMILIAR_PROJECT_DIR=/workspace \
  -e FAMILIAR_API_KEY="$FAMILIAR_API_KEY" \
  -e FAMILIAR_BASE_URL="$FAMILIAR_BASE_URL" \
  -e FAMILIAR_CHAT_MODEL="$FAMILIAR_CHAT_MODEL" \
  -e FAMILIAR_PROVIDER=openai_compatible \
  --network=host \
  familiar fam init
```

### What a sandbox protects you from

- LLM-generated `rm -rf /` or equivalent destructive commands
- File writes outside your project directory
- Arbitrary shell commands with network access

### What a sandbox does NOT protect you from

- Data exfiltration via the LLM provider API (the LLM sees your code and sends it to the provider)
- Prompt injection that steals secrets from environment variables the container has
- The LLM provider logging or training on your code (check your provider's data policy)

## Development

```bash
cd familiar
mix deps.get
mix test                    # 1244 tests + 8 properties
mix credo --strict          # Static analysis
mix dialyzer                # Type checking
mix sobelow                 # Security scanning
mix format --check-formatted
```

The pre-commit hook runs all six checks. Zero tolerance for flaky tests — new test files are stress-tested 50x before merge.

## License

[AGPL-3.0-only](LICENSE)
