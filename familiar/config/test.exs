import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :familiar, Familiar.Repo,
  database: Path.expand("../familiar_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :familiar, FamiliarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9tsm5XAAgR6d0XE4fL57rB+dqMpyVdcmJML1aMrhNmwnoW5A19DkpPY5nTmT17ub",
  server: false

# Disable daemon, file watcher, and extensions auto-start in test (tests start them manually)
config :familiar, start_daemon: false
config :familiar, start_file_watcher: false
config :familiar, :extensions, []

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Behaviour port mocks for hexagonal architecture
config :familiar, Familiar.Providers.LLM, Familiar.Providers.LLMMock
config :familiar, Familiar.Knowledge.Embedder, Familiar.Knowledge.EmbedderMock
config :familiar, Familiar.System.FileSystem, Familiar.System.FileSystemMock
config :familiar, Familiar.System.Shell, Familiar.System.ShellMock
config :familiar, Familiar.System.Notifications, Familiar.System.NotificationsMock
config :familiar, Familiar.System.Clock, Familiar.System.ClockMock

# Fast timeouts for hooks tests (defaults are too slow for test suite)
config :familiar, Familiar.Hooks,
  handler_timeout: 50,
  event_handler_timeout: 50,
  mailbox_warning_threshold: 5
