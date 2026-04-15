# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :uptrack,
  env: config_env(),
  ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo],
  generators: [timestamp_type: :utc_datetime],
  app_url: "http://localhost:4000",
  frontend_url: "http://localhost:3000",
  cors_origins: ["http://localhost:3000"],
  # Check client: Mint (process-less, 22% less RAM) or Gun (persistent process) or Finch (pool)
  check_client: Uptrack.Monitoring.CheckClient.Mint,
  # Region identifier for multi-region consensus (override via NODE_REGION env var)
  node_region: "eu",
  victoriametrics_vminsert_url: nil,
  victoriametrics_vmselect_url: nil

# AppRepo handles all migrations (app schema + oban schema)
# ObanRepo uses same database but separate connection pool
# This prevents job queue from starving app queries
config :uptrack, Uptrack.AppRepo,
  migration_lock: :pg_advisory_lock

# Nebulex cache (Local ETS adapter — each node has its own cache)
config :uptrack, Uptrack.Cache,
  gc_interval: :timer.minutes(5),
  max_size: 10_000,
  allocated_memory: 100_000_000

# Rate limiting configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

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
  client_id: "not-set",
  client_secret: "not-set"

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: "not-set",
  client_secret: "not-set"

# Configure Tesla (disable deprecation warnings)
config :tesla, disable_deprecated_builder_warning: true

# Boruta OAuth 2.0 server
config :boruta, Boruta.Oauth,
  repo: Uptrack.AppRepo,
  cache_backend: Boruta.Cache,
  contexts: [resource_owners: Uptrack.Accounts],
  token_generator: Uptrack.OAuth.TokenGenerator,
  access_token_ttl: 24 * 60 * 60,
  authorization_code_ttl: 3 * 60,
  refresh_token_ttl: 30 * 24 * 60 * 60

# Configure Oban for background jobs
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  prefix: "oban",
  plugins: [
    {Oban.Plugins.Pruner, max_age: 300},
    {Oban.Plugins.Cron, crontab: [
      # Monitor checks now handled by GenServer-per-monitor (MonitorProcess)
      # SchedulerWorker removed — no longer needed
      # Check for missed heartbeats every minute
      {"* * * * *", Uptrack.Monitoring.HeartbeatCheckerWorker},
      # Run idle prevention every 3 hours to prevent Oracle Always Free reclamation
      {"0 */3 * * *", Uptrack.Monitoring.IdlePreventionWorker},
      # Process batched notification digests every hour
      {"0 * * * *", Uptrack.Alerting.NotificationBatchWorker},
      # Activate/complete maintenance windows every minute
      {"* * * * *", Uptrack.Maintenance.MaintenanceWorker},
      # Send weekly uptime reports every Monday at 9am UTC
      {"0 9 * * 1", Uptrack.Reports.WeeklyReportWorker},
      # Refresh disposable email domain list daily at 3am UTC
      {"0 3 * * *", Uptrack.AbusePrevention.DisposableEmailWorker},
      # Clean up notification deliveries older than 7 days daily at 3:30am UTC
      {"30 3 * * *", Uptrack.Alerting.DeliveryCleanupWorker}
    ]}
  ],
  queues: [
    default: 10,
    # monitor_checks queue removed — checks now via GenServer-per-monitor
    email_critical: 50,
    email_digest: 10,
    email_system: 5,
    mailers: 5
  ]

config :appsignal, :config,
  otp_app: :uptrack,
  name: "Uptrack API",
  active: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
