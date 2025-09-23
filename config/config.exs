# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :uptrack,
  ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo, Uptrack.ResultsRepo],
  generators: [timestamp_type: :utc_datetime]

# Separate migration sources to eliminate shared schema_migrations conflicts
config :uptrack, Uptrack.AppRepo,
  migration_source: "app_schema_migrations",
  migration_lock: :pg_advisory_lock

config :uptrack, Uptrack.ObanRepo,
  migration_source: "oban_schema_migrations",
  migration_lock: :pg_advisory_lock

config :uptrack, Uptrack.ResultsRepo,
  migration_source: "results_schema_migrations",
  migration_lock: :pg_advisory_lock

# Configures the endpoint
config :uptrack, UptrackWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: UptrackWeb.ErrorHTML, json: UptrackWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Uptrack.PubSub,
  live_view: [signing_salt: "l/VU7cMd"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :uptrack, Uptrack.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  uptrack: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  uptrack: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, []},
    google: {Ueberauth.Strategy.Google, []}
  ]

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# Configure Tesla (disable deprecation warnings)
config :tesla, disable_deprecated_builder_warning: true

# Configure Oban for background jobs
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 300},
    {Oban.Plugins.Cron, crontab: [
      # Run monitor checks every 30 seconds
      {"*/30 * * * * *", Uptrack.Monitoring.SchedulerWorker}
    ]}
  ],
  queues: [
    default: 10,
    monitor_checks: 25,
    alerts: 5
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
