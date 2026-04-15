# Sandboxing

Familiar executes LLM-generated tool calls — including `write_file`, `delete_file`, and `run_command` — without any runtime safety layer. The LLM is an untrusted actor. The only meaningful security boundary is the OS sandbox you choose to run Familiar inside.

## Why no runtime safety

Familiar previously shipped a Safety extension that pattern-matched on dangerous tool names (`run_command`, `delete_file`, etc.) and vetoed calls outside the project directory. It was removed because it provided false confidence:

- An adversarial LLM can trivially bypass name-based filters (e.g., calling `sh` instead of `run_command`).
- External MCP tools have arbitrary names that don't match any built-in pattern.
- A "safety" layer that can be trivially bypassed is worse than no layer at all — it discourages users from setting up real isolation.

The honest approach: tell you the risk, give you a container recipe, and get out of the way.

## Recommended: Docker

The included `Dockerfile` and `docker-compose.yml` provide a ready-to-use container:

```bash
cd familiar
docker compose run --rm familiar fam init
docker compose run --rm familiar fam chat
```

Or build and run directly:

```bash
docker build -t familiar familiar/
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -e FAMILIAR_API_KEY="$FAMILIAR_API_KEY" \
  -e FAMILIAR_BASE_URL="$FAMILIAR_BASE_URL" \
  -e FAMILIAR_CHAT_MODEL="$FAMILIAR_CHAT_MODEL" \
  -e FAMILIAR_PROVIDER=openai_compatible \
  familiar fam chat
```

### Hardened Docker flags

For more isolation than the defaults:

```bash
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -e FAMILIAR_API_KEY="$FAMILIAR_API_KEY" \
  -e FAMILIAR_BASE_URL="$FAMILIAR_BASE_URL" \
  -e FAMILIAR_CHAT_MODEL="$FAMILIAR_CHAT_MODEL" \
  -e FAMILIAR_PROVIDER=openai_compatible \
  --network=none \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  familiar fam chat
```

Flag notes:

- `--network=none` blocks all network access. This only works for local models (Ollama running on the host via `--add-host=host.docker.internal:host-gateway`). For remote LLM providers, omit this flag or create a custom Docker network that restricts egress to your provider's IP range. Avoid `--network=host` — it removes all network isolation.
- `--read-only` makes the root filesystem read-only. Combined with `--tmpfs /tmp`, the LLM can only write to `/workspace` (your mounted project) and `/tmp`.
- `--cap-drop ALL` drops all Linux capabilities. The container cannot mount filesystems, change network config, or escalate privileges.

## Podman

If you prefer rootless containers without a daemon:

```bash
podman build -t familiar familiar/
podman run --rm -it \
  -v "$(pwd):/workspace:Z" \
  -e FAMILIAR_API_KEY="$FAMILIAR_API_KEY" \
  -e FAMILIAR_BASE_URL="$FAMILIAR_BASE_URL" \
  -e FAMILIAR_CHAT_MODEL="$FAMILIAR_CHAT_MODEL" \
  -e FAMILIAR_PROVIDER=openai_compatible \
  --network=none \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  familiar fam chat
```

The `:Z` suffix on the volume mount handles SELinux relabeling. On non-SELinux systems, omit it.

## Ephemeral VMs

For maximum isolation (e.g., running untrusted code from the LLM against a production database dump):

### Firecracker

```bash
# Create a rootfs with Familiar installed, boot a microVM,
# mount your project via virtio-fs, run fam, destroy the VM.
# Firecracker boots in <125ms — fast enough for interactive use.
```

Firecracker is what AWS Lambda uses. Each invocation gets a fresh VM with no persistent state. Network is disabled by default.

### QEMU

```bash
qemu-system-x86_64 \
  -m 2G -smp 2 \
  -drive file=familiar.qcow2,format=qcow2 \
  -virtfs local,path=$(pwd),mount_tag=workspace,security_model=mapped \
  -net none \
  -nographic
```

Heavier than Firecracker but works on any Linux/macOS host without custom kernel support.

## What a sandbox does NOT protect you from

Even inside a container or VM, these risks remain:

- **Data exfiltration via the LLM provider API.** The LLM sees your code (it's in the prompt) and sends it to the provider. If the provider is compromised or logs prompts, your code is exposed. Mitigation: use a local model (Ollama) for sensitive projects.

- **Prompt injection that steals secrets.** If you pass `FAMILIAR_API_KEY` or other secrets as environment variables, a prompt-injected LLM can read them via `run_command` (e.g., `env | grep KEY`) and exfiltrate them in the next API call. Mitigation: use short-lived tokens, restrict env vars to the minimum needed, and monitor API call logs.

- **Provider data policies.** Your LLM provider may log, store, or train on the prompts and completions Familiar sends. This includes your source code, file contents, and shell command output. Check your provider's data retention and training policies before pointing Familiar at proprietary code.

- **Malicious code execution within the sandbox.** The LLM can write and execute arbitrary code inside the container. If your project directory contains credentials, database files, or other sensitive data, the LLM has full access to them. Mount only what the LLM needs to see.
