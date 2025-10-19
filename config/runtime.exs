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
  # Multi-repo configuration
  app_database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST/DATABASE?search_path=app,public
      """

  oban_database_url =
    System.get_env("OBAN_DATABASE_URL") ||
      raise """
      environment variable OBAN_DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST/DATABASE?search_path=oban,public
      """

  results_database_url =
    System.get_env("RESULTS_DATABASE_URL") ||
      raise """
      environment variable RESULTS_DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST/DATABASE?search_path=results,public
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Per-repo pool sizes for optimized resource allocation
  # Each repo handles different workloads:
  # - AppRepo: Light OLTP (users, configs, incidents)
  # - ObanRepo: High job throughput (monitor checks)
  # - ResultsRepo: Batch inserts (monitoring data)
  app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
  oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")
  results_pool_size = String.to_integer(System.get_env("RESULTS_POOL_SIZE") || "15")

  # AppRepo configuration - Light OLTP workload
  config :uptrack, Uptrack.AppRepo,
    url: app_database_url,
    pool_size: app_pool_size,
    queue_target: 50,
    queue_interval: 5000,
    socket_options: maybe_ipv6

  # ObanRepo configuration - High job throughput
  config :uptrack, Uptrack.ObanRepo,
    url: oban_database_url,
    pool_size: oban_pool_size,
    queue_target: 100,
    queue_interval: 1000,
    socket_options: maybe_ipv6

  # ResultsRepo configuration - Batch inserts
  config :uptrack, Uptrack.ResultsRepo,
    url: results_database_url,
    pool_size: results_pool_size,
    queue_target: 75,
    queue_interval: 2000,
    socket_options: maybe_ipv6

  # Oban configuration with node identification
  config :uptrack, Oban,
    repo: Uptrack.ObanRepo,
    node: System.get_env("OBAN_NODE_NAME", "unknown-node"),
    queues: [
      checks: String.to_integer(System.get_env("OBAN_CHECKS_CONCURRENCY", "50")),
      webhooks: String.to_integer(System.get_env("OBAN_WEBHOOKS_CONCURRENCY", "10")),
      incidents: String.to_integer(System.get_env("OBAN_INCIDENTS_CONCURRENCY", "5"))
    ],
    plugins: [
      {Oban.Plugins.Pruner, max_age: 604_800},  # 7 days
      Oban.Plugins.Repeater,
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)},
      {Oban.Plugins.Cron, crontab: [
        # Run monitor scheduling every 30 seconds
        {"*/30 * * * * *", Uptrack.Monitoring.SchedulerWorker}
      ]}
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

  config :uptrack, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

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

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :uptrack, Uptrack.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
