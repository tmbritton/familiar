# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :familiar,
  ecto_repos: [Familiar.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :familiar, FamiliarWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FamiliarWeb.ErrorHTML, json: FamiliarWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Familiar.PubSub,
  live_view: [signing_salt: "tYbtlqSM"]

# Extensions (loaded at startup)
config :familiar, :extensions, [Familiar.Extensions.KnowledgeStore, Familiar.Extensions.MCPClient]

# Provider adapter configuration (overridden by test.exs for mocks)
config :familiar, Familiar.Providers.LLM, Familiar.Providers.OllamaAdapter
config :familiar, Familiar.Knowledge.Embedder, Familiar.Providers.OllamaEmbedder
config :familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem

# Expected embedding vector length. Matches `openai/text-embedding-3-small`.
# Changing this requires a matching migration to recreate the sqlite-vec
# virtual table. Tests read this via `Familiar.Knowledge.embedding_dimensions/0`.
config :familiar, :embedding_dimensions, 1536
config :familiar, Familiar.System.Shell, Familiar.System.RealShell
config :familiar, Familiar.System.Clock, Familiar.System.RealClock

# Ollama provider settings
config :familiar, :ollama,
  base_url: "http://localhost:11434",
  chat_model: "llama3.2",
  embedding_model: "nomic-embed-text",
  receive_timeout: 120_000

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  familiar: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
