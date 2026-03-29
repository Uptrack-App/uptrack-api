import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Configure all three repos for testing
config :uptrack, Uptrack.AppRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "uptrack_test#{System.get_env("MIX_TEST_PARTITION")}",
  # public first so Ecto finds schema_migrations in public (not the app schema copy)
  parameters: [search_path: "public,app"],
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :uptrack, Uptrack.ObanRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "uptrack_test#{System.get_env("MIX_TEST_PARTITION")}",
  parameters: [search_path: "oban,public"],
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :uptrack, Uptrack.ResultsRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "uptrack_test#{System.get_env("MIX_TEST_PARTITION")}",
  parameters: [search_path: "results,public"],
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uptrack, UptrackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "REMOVED_TEST_SECRET_KEY_BASE",
  server: false

# In test we don't send emails
config :uptrack, Uptrack.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Disable Oban queues and plugins in test, stub job insertion
config :uptrack, Oban, testing: :manual, queues: false, plugins: false

# Use mock Paddle client in tests
config :uptrack, :paddle_client, Uptrack.Billing.PaddleClientMock

# Default to Paddle provider in tests (matches production default)
config :uptrack, :payment_provider, Uptrack.Billing.Paddle.PaddleProvider

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
