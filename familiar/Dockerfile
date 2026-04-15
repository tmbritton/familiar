# Familiar — Containerized Agent Harness
#
# Build:   docker build -t familiar .
# Init:    docker run --rm -it -v $(pwd):/workspace \
#            -e FAMILIAR_API_KEY=sk-xxx familiar fam init
# Chat:    docker run --rm -it -v $(pwd):/workspace \
#            -e FAMILIAR_API_KEY=sk-xxx familiar fam chat
#
# See docs/sandboxing.md for hardened flags (--read-only, --cap-drop, etc.)

# === Builder stage ===
FROM hexpm/elixir:1.19.5-erlang-28.2-debian-bookworm-20260202-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Dependencies (cache layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Application code
COPY config config/
COPY lib lib/
COPY priv priv/
COPY rel rel/
RUN mix compile --warnings-as-errors

# Build release (bundles ERTS — no Erlang needed at runtime)
RUN mix release familiar

# === Runtime stage ===
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 libncurses6 libssl3 ca-certificates \
      libsqlite3-0 git locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8

# Non-root user
RUN groupadd -r familiar && useradd -r -g familiar -m familiar

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/familiar /app
RUN chmod +x /app/bin/fam

# Put fam CLI wrapper on PATH
RUN ln -s /app/bin/fam /usr/local/bin/fam

ENV FAMILIAR_PROJECT_DIR=/workspace

WORKDIR /workspace
USER familiar

CMD ["fam", "help"]
