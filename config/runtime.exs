import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/uptrack start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :uptrack, UptrackWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Single database URL (same for app and oban)
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Separate connection pools to prevent job queue from starving app queries
  app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "30")
  oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "60")

  # AppRepo - app schema + migrations
  config :uptrack, Uptrack.AppRepo,
    url: database_url,
    pool_size: app_pool_size,
    queue_target: 50,
    queue_interval: 5000,
    socket_options: maybe_ipv6

  # ObanRepo - same database, separate pool for job queue
  # Separate pool isolates Oban from app queries (prevents job starvation)
  config :uptrack, Uptrack.ObanRepo,
    url: database_url,
    pool_size: oban_pool_size,
    queue_target: 100,
    queue_interval: 1000,
    socket_options: maybe_ipv6

  # Oban configuration with node identification
  config :uptrack, Oban,
    repo: Uptrack.AppRepo,
    prefix: "oban",
    node: System.get_env("OBAN_NODE_NAME", "unknown-node"),
    queues: [
      default: 10,
      # monitor_checks removed — GenServer-per-monitor handles checks
      alerts: String.to_integer(System.get_env("OBAN_ALERTS_CONCURRENCY", "5"))
    ],
    plugins: [
      {Oban.Plugins.Pruner, max_age: 604_800},  # 7 days
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)}
      # Monitor checks now handled by GenServer-per-monitor (MonitorProcess)
      # SchedulerWorker and Repeater removed
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :uptrack, app_url: System.get_env("APP_URL") || "https://#{host}"
  config :uptrack, frontend_url: System.get_env("FRONTEND_URL") || "https://#{host}"

  # CORS allowed origins (comma-separated, e.g. "https://app.uptrack.dev,https://uptrack.dev")
  if cors = System.get_env("CORS_ORIGINS") do
    config :uptrack, cors_origins: String.split(cors, ",", trim: true)
  end

  # Multi-region consensus: NODE_REGION env var overrides compile-time default
  if region = System.get_env("NODE_REGION") do
    config :uptrack, node_region: region
  end

  # VictoriaMetrics cluster endpoints (nil = disabled)
  if vminsert = System.get_env("VICTORIAMETRICS_VMINSERT_URL") do
    config :uptrack, victoriametrics_vminsert_url: vminsert
  end

  if vmselect = System.get_env("VICTORIAMETRICS_VMSELECT_URL") do
    config :uptrack, victoriametrics_vmselect_url: vmselect
  end

  config :uptrack, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # OAuth provider credentials (read at runtime from env vars)
  if github_id = System.get_env("GITHUB_CLIENT_ID") do
    config :ueberauth, Ueberauth.Strategy.Github.OAuth,
      client_id: github_id,
      client_secret: System.get_env("GITHUB_CLIENT_SECRET")
  end

  if google_id = System.get_env("GOOGLE_CLIENT_ID") do
    config :ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: google_id,
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
  end

  # Slack OAuth + slash commands
  if slack_id = System.get_env("SLACK_CLIENT_ID") do
    config :uptrack,
      slack_client_id: slack_id,
      slack_client_secret: System.get_env("SLACK_CLIENT_SECRET"),
      slack_signing_secret: System.get_env("SLACK_SIGNING_SECRET")
  end

  # Telegram bot (optional — Connect Telegram disabled if not set)
  if tg_token = System.get_env("TELEGRAM_BOT_TOKEN") do
    config :uptrack,
      telegram_bot_token: tg_token,
      telegram_bot_username: System.get_env("TELEGRAM_BOT_USERNAME", "UptrackAppBot"),
      telegram_webhook_secret: System.get_env("TELEGRAM_WEBHOOK_SECRET", "uptrack_tg_#{:crypto.hash(:sha256, tg_token) |> Base.url_encode64(padding: false) |> binary_part(0, 16)}")
  end

  # Paddle billing (optional — billing disabled if not set)
  if paddle_api_key = System.get_env("PADDLE_API_KEY") do
    config :uptrack, :paddle,
      api_key: paddle_api_key,
      webhook_secret: System.get_env("PADDLE_WEBHOOK_SECRET"),
      base_url: System.get_env("PADDLE_BASE_URL", "https://api.paddle.com"),
      checkout_url: System.get_env("PADDLE_CHECKOUT_URL", "https://checkout.paddle.com"),
      price_id_pro: System.get_env("PADDLE_PRICE_ID_PRO"),
      price_id_pro_annual: System.get_env("PADDLE_PRICE_ID_PRO_ANNUAL"),
      price_id_team: System.get_env("PADDLE_PRICE_ID_TEAM"),
      price_id_team_annual: System.get_env("PADDLE_PRICE_ID_TEAM_ANNUAL"),
      price_id_business: System.get_env("PADDLE_PRICE_ID_BUSINESS"),
      price_id_business_annual: System.get_env("PADDLE_PRICE_ID_BUSINESS_ANNUAL")
  end

  config :uptrack, UptrackWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :uptrack, UptrackWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :uptrack, UptrackWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Production mailer: configurable via MAILER_ADAPTER env var.
  # Supported: "brevo", "mailgun", "postmark", "sendgrid". Falls back to logger.
  case System.get_env("MAILER_ADAPTER") do
    "brevo" ->
      config :uptrack, Uptrack.Mailer,
        adapter: Swoosh.Adapters.Brevo,
        api_key: System.get_env("BREVO_API_KEY")

    "mailgun" ->
      config :uptrack, Uptrack.Mailer,
        adapter: Swoosh.Adapters.Mailgun,
        api_key: System.get_env("MAILGUN_API_KEY"),
        domain: System.get_env("MAILGUN_DOMAIN")

    "postmark" ->
      config :uptrack, Uptrack.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: System.get_env("POSTMARK_API_KEY")

    "sendgrid" ->
      config :uptrack, Uptrack.Mailer,
        adapter: Swoosh.Adapters.Sendgrid,
        api_key: System.get_env("SENDGRID_API_KEY")

    _ ->
      # Log emails to stdout (visible in journalctl) until a real adapter is configured
      config :uptrack, Uptrack.Mailer, adapter: Swoosh.Adapters.Logger
  end
end
