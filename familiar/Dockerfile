# Familiar — Containerized Agent Harness
#
# Build:  docker build -t familiar .
# Start:  docker run -d --name fam -v $(pwd):/project \
#           -e FAMILIAR_API_KEY=sk-xxx \
#           -e FAMILIAR_PROVIDER=openai_compatible \
#           familiar
# Use:    docker exec -it fam fam chat
# Alias:  alias fam='docker exec -it fam fam'

# === Build & Runtime (single stage for now — uses Mix) ===
FROM elixir:1.19.5-otp-28-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential sqlite3 libsqlite3-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install dependencies (cache layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Copy application source
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# Compile
RUN mix compile

# Create the CLI wrapper script
RUN cat > /usr/local/bin/fam << 'EOF'
#!/bin/bash
set -e
cd /app
exec mix run --no-halt -e "Familiar.CLI.Main.main(System.argv())" -- "$@"
EOF
RUN chmod +x /usr/local/bin/fam

# Set defaults
ENV FAMILIAR_PROJECT_DIR=/project
ENV FAMILIAR_PROVIDER=openai_compatible
ENV FAMILIAR_BASE_URL=https://api.deepseek.com
ENV FAMILIAR_CHAT_MODEL=deepseek-chat

WORKDIR /project

# Container stays alive for docker exec
CMD ["tail", "-f", "/dev/null"]
