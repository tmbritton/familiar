# Familiar — Containerized Agent Harness
#
# Build:  docker build -t familiar .
# Start:  docker run -d --name fam -v $(pwd):/project \
#           -e FAMILIAR_API_KEY=sk-xxx \
#           -e FAMILIAR_PROVIDER=openai_compatible \
#           familiar
# Use:    docker exec -it fam fam chat
# Alias:  alias fam='docker exec -it fam fam'
#
# Note: Each command boots the OTP app (~5s). A future optimization would
# use an Elixir release with a persistent node and RPC for instant commands.

FROM elixir:1.19.5-otp-28-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential sqlite3 libsqlite3-dev ca-certificates \
      inotify-tools procps && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Dependencies (cache layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Application source
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# Compile
RUN mix compile

# CLI wrapper — bootstraps on first run, executes commands
RUN cat > /usr/local/bin/fam << 'SCRIPT'
#!/bin/bash
set -e
cd /app

# === Bootstrap on first run ===
if [ ! -d "/project/.familiar" ]; then
  echo "[familiar] First run — initializing project structure..."
  mkdir -p /project/.familiar/roles /project/.familiar/skills /project/.familiar/workflows
fi

rm -f /project/.familiar/shutdown_marker /project/.familiar/daemon.pid /project/.familiar/daemon.lock 2>/dev/null

if [ ! -f "/project/.familiar/familiar.db" ]; then
  echo "[familiar] Creating database..."
  mix ecto.create 2>/dev/null || true
fi
mix ecto.migrate --quiet 2>/dev/null || true

if [ ! -f "/project/.familiar/roles/user-manager.md" ]; then
  echo "[familiar] Installing default roles, skills, and workflows..."
  mix run -e "Familiar.Knowledge.DefaultFiles.install(\"/project/.familiar\")" 2>/dev/null || true
fi
if [ ! -f "/project/.familiar/config.toml" ]; then
  echo "[familiar] Generating default config..."
  mix run -e "Familiar.Config.Generator.generate_default(\"/project/.familiar\", nil)" 2>/dev/null || true
fi

# === Run the command ===
exec mix run --no-halt -e "Familiar.CLI.Main.main(System.argv())" -- "$@"
SCRIPT
RUN chmod +x /usr/local/bin/fam

# Environment defaults
ENV FAMILIAR_PROJECT_DIR=/project
ENV FAMILIAR_PROVIDER=openai_compatible
ENV FAMILIAR_BASE_URL=https://api.deepseek.com
ENV FAMILIAR_CHAT_MODEL=deepseek-chat
ENV DATABASE_PATH=/project/.familiar/familiar.db
ENV SECRET_KEY_BASE=familiar-container-default-key-not-for-production-use-replace-me
ENV LOG_LEVEL=warning

WORKDIR /project

# Keep container alive for docker exec
CMD ["tail", "-f", "/dev/null"]
