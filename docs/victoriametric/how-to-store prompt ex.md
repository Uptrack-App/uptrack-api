 Got it! Let me tailor the VictoriaMetrics integration specifically for your Uptrack.app project in /repos/uptrack.

  ---
  🎯 VictoriaMetrics Setup for Uptrack.app

  Based on your uptime monitoring app context, here's the recommended setup:

  ---
  📊 Key Metrics to Track for Uptrack

  1. Uptime Check Metrics (Core Feature)

  # Uptime status (1=up, 0=down)
  uptrack_monitor_status{monitor_id="123", url="example.com"}

  # Response time in milliseconds
  uptrack_monitor_response_time_ms{monitor_id="123", url="example.com"}

  # Check success/failure counts
  uptrack_checks_total{monitor_id="123", status="success|failure"}

  # SSL certificate expiry days
  uptrack_ssl_expiry_days{monitor_id="123", domain="example.com"}

  2. Alert Metrics

  # Alert notifications sent
  uptrack_alerts_sent_total{monitor_id="123", channel="email|slack|webhook"}

  # Alert response time
  uptrack_alert_delivery_duration_seconds{channel="email"}

  3. System Health (Auto-tracked by PromEx)

  # Phoenix request metrics
  phoenix_http_requests_total{method="GET", status="200"}
  phoenix_http_request_duration_seconds

  # Oban job metrics (for scheduled checks)
  oban_jobs_total{queue="uptime_checks", state="success"}
  oban_queue_size{queue="uptime_checks"}

  # Database metrics
  ecto_query_duration_seconds

  ---
  🔧 Implementation for Uptrack

  Step 1: Add Dependencies

  # /repos/uptrack/mix.exs
  def deps do
    [
      {:prom_ex, "~> 1.10"},
      # ... existing deps
    ]
  end

  Step 2: Create PromEx Module

  # /repos/uptrack/lib/uptrack/prom_ex.ex
  defmodule Uptrack.PromEx do
    use PromEx, otp_app: :uptrack

    alias PromEx.Plugins

    @impl true
    def plugins do
      [
        # Built-in plugins
        Plugins.Phoenix,
        Plugins.Ecto,
        Plugins.Oban,           # Critical for scheduled uptime checks!
        Plugins.PhoenixLiveView,
        Plugins.Beam,

        # Custom uptime monitoring metrics
        Uptrack.PromEx.UptimeMetrics
      ]
    end

    @impl true
    def dashboard_assigns do
      [
        datasource_id: "victoriametrics",
        default_selected_interval: "1m"  # Short interval for uptime monitoring
      ]
    end

    @impl true
    def dashboards do
      [
        {:prom_ex, "application.json"},
        {:prom_ex, "oban.json"},  # Monitor uptime check jobs
        {:prom_ex, "beam.json"}
      ]
    end
  end

  Step 3: Create Custom Uptime Metrics

  # /repos/uptrack/lib/uptrack/prom_ex/uptime_metrics.ex
  defmodule Uptrack.PromEx.UptimeMetrics do
    use PromEx.Plugin

    @impl true
    def event_metrics(_opts) do
      [
        # Monitor status (1=up, 0=down)
        last_value(
          [:uptrack, :monitor, :status],
          event_name: [:uptrack, :monitor, :check, :complete],
          measurement: :status,
          description: "Monitor status (1=up, 0=down)",
          tags: [:monitor_id, :monitor_name, :url]
        ),

        # Response time distribution
        distribution(
          [:uptrack, :monitor, :response_time, :milliseconds],
          event_name: [:uptrack, :monitor, :check, :complete],
          measurement: :response_time,
          description: "Monitor response time",
          unit: {:native, :millisecond},
          tags: [:monitor_id, :monitor_name, :url],
          reporter_options: [
            buckets: [50, 100, 200, 500, 1000, 2000, 5000, 10000]
          ]
        ),

        # Check counter (success/failure)
        counter(
          [:uptrack, :monitor, :checks, :total],
          event_name: [:uptrack, :monitor, :check, :complete],
          description: "Total uptime checks performed",
          tags: [:monitor_id, :status]
        ),

        # SSL certificate expiry
        last_value(
          [:uptrack, :monitor, :ssl, :expiry_days],
          event_name: [:uptrack, :monitor, :ssl, :checked],
          measurement: :days_until_expiry,
          description: "Days until SSL certificate expires",
          tags: [:monitor_id, :domain]
        ),

        # Alert metrics
        counter(
          [:uptrack, :alerts, :sent, :total],
          event_name: [:uptrack, :alert, :sent],
          description: "Total alerts sent",
          tags: [:monitor_id, :channel, :status]
        ),

        distribution(
          [:uptrack, :alerts, :delivery, :duration],
          event_name: [:uptrack, :alert, :sent],
          measurement: :duration,
          description: "Alert delivery duration",
          unit: {:native, :millisecond},
          tags: [:channel],
          reporter_options: [
            buckets: [100, 500, 1000, 2000, 5000]
          ]
        )
      ]
    end
  end

  Step 4: Instrument Your Uptime Check Code

  # /repos/uptrack/lib/uptrack/monitors/checker.ex
  defmodule Uptrack.Monitors.Checker do
    @moduledoc """
    Performs uptime checks and emits telemetry events
    """

    def check_monitor(monitor) do
      start_time = System.monotonic_time()

      result = perform_http_check(monitor.url)

      duration = System.monotonic_time() - start_time
      response_time_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Emit telemetry event for metrics
      :telemetry.execute(
        [:uptrack, :monitor, :check, :complete],
        %{
          status: if(result.success?, do: 1, else: 0),
          response_time: response_time_ms
        },
        %{
          monitor_id: monitor.id,
          monitor_name: monitor.name,
          url: monitor.url,
          status: if(result.success?, do: "success", else: "failure")
        }
      )

      result
    end

    defp perform_http_check(url) do
      case Req.get(url, connect_options: [timeout: 10_000]) do
        {:ok, %{status: status}} when status in 200..299 ->
          %{success?: true, status: status}

        {:ok, %{status: status}} ->
          %{success?: false, status: status}

        {:error, reason} ->
          %{success?: false, error: reason}
      end
    end
  end

  # /repos/uptrack/lib/uptrack/monitors/ssl_checker.ex
  defmodule Uptrack.Monitors.SSLChecker do
    def check_ssl_expiry(monitor) do
      case get_ssl_certificate(monitor.url) do
        {:ok, cert} ->
          days_until_expiry = calculate_expiry_days(cert)

          :telemetry.execute(
            [:uptrack, :monitor, :ssl, :checked],
            %{days_until_expiry: days_until_expiry},
            %{
              monitor_id: monitor.id,
              domain: extract_domain(monitor.url)
            }
          )

          {:ok, days_until_expiry}

        {:error, _} = error ->
          error
      end
    end

    defp calculate_expiry_days(cert) do
      # Implementation to calculate days until cert expires
    end

    defp extract_domain(url) do
      URI.parse(url).host
    end

    defp get_ssl_certificate(url) do
      # Implementation to fetch SSL certificate
    end
  end

  # /repos/uptrack/lib/uptrack/alerts/notifier.ex
  defmodule Uptrack.Alerts.Notifier do
    def send_alert(monitor, channel, message) do
      start_time = System.monotonic_time()

      result = do_send_alert(channel, message)

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:uptrack, :alert, :sent],
        %{duration: System.convert_time_unit(duration, :native, :millisecond)},
        %{
          monitor_id: monitor.id,
          channel: channel.type, # "email", "slack", "webhook"
          status: if(match?({:ok, _}, result), do: "success", else: "failure")
        }
      )

      result
    end

    defp do_send_alert("email", message) do
      # Send email
    end

    defp do_send_alert("slack", message) do
      # Send Slack notification
    end

    defp do_send_alert("webhook", message) do
      # Send webhook
    end
  end

  Step 5: Add to Supervision Tree

  # /repos/uptrack/lib/uptrack/application.ex
  defmodule Uptrack.Application do
    use Application

    def start(_type, _args) do
      children = [
        Uptrack.Repo,
        UptrackWeb.Endpoint,

        # Add PromEx
        Uptrack.PromEx,

        # Oban for scheduled checks
        {Oban, oban_config()},

        # ... other children
      ]

      opts = [strategy: :one_for_one, name: Uptrack.Supervisor]
      Supervisor.start_link(children, opts)
    end

    defp oban_config do
      Application.fetch_env!(:uptrack, Oban)
    end
  end

  Step 6: Add Metrics Endpoint

  # /repos/uptrack/lib/uptrack_web/router.ex
  defmodule UptrackWeb.Router do
    use UptrackWeb, :router

    # ... existing pipelines

    # Metrics endpoint (protected!)
    pipeline :metrics do
      plug :accepts, ["text"]
      plug BasicAuth, use_config: {:uptrack, :metrics_auth}
    end

    scope "/metrics" do
      pipe_through :metrics
      forward "/", PromEx.Plug, prom_ex_module: Uptrack.PromEx
    end

    # ... rest of routes
  end

  Config for auth:

  # /repos/uptrack/config/runtime.exs
  config :uptrack, :metrics_auth,
    username: System.get_env("METRICS_USERNAME") || "admin",
    password: System.get_env("METRICS_PASSWORD") || "changeme"

  Step 7: Configure VictoriaMetrics Scraping

  # victoriametrics-config.yml (or prometheus.yml format)
  scrape_configs:
    - job_name: 'uptrack'
      scrape_interval: 30s  # Check every 30 seconds
      basic_auth:
        username: 'admin'
        password: 'changeme'
      static_configs:
        - targets: ['uptrack.app:4000']
      metrics_path: '/metrics'

  Start VictoriaMetrics with scraping:

  # Using vmagent (recommended)
  vmagent \
    -promscrape.config=victoriametrics-config.yml \
    -remoteWrite.url=http://victoriametrics:8428/api/v1/write

  # Or use VictoriaMetrics built-in scraping
  victoria-metrics \
    -promscrape.config=victoriametrics-config.yml \
    -storageDataPath=/var/lib/victoria-metrics \
    -retentionPeriod=15M

  ---
  📈 Useful Queries for Uptrack Dashboard

  Uptime Percentage (Last 24h)

  avg_over_time(uptrack_monitor_status{monitor_id="123"}[24h]) * 100

  Average Response Time

  avg(uptrack_monitor_response_time_milliseconds{monitor_id="123"})

  Monitors Down Right Now

  count(uptrack_monitor_status == 0)

  Check Success Rate

  rate(uptrack_monitor_checks_total{status="success"}[5m]) /
  rate(uptrack_monitor_checks_total[5m]) * 100

  P95 Response Time

  histogram_quantile(0.95,
    rate(uptrack_monitor_response_time_milliseconds_bucket[5m])
  )

  SSL Certificates Expiring Soon (<30 days)

  uptrack_monitor_ssl_expiry_days < 30

  Alert Delivery Failures

  rate(uptrack_alerts_sent_total{status="failure"}[1h])

  Oban Job Queue Size (for scheduled checks)

  oban_queue_size{queue="uptime_checks"}

  ---
  🎨 Grafana Dashboard Example

  Create a Grafana dashboard with these panels:

  1. Monitor Status Overview - Table showing all monitors with current status
  2. Uptime Percentage - Gauge for each monitor (target: >99.9%)
  3. Response Time Trends - Line graph over 24h
  4. Alerts Sent - Counter with breakdown by channel
  5. SSL Certificate Expiry - Bar chart with days remaining
  6. Oban Job Performance - Queue size and processing rate

  ---
  🚀 Quick Start Commands

  # In /repos/uptrack

  # 1. Add dependency
  echo '{:prom_ex, "~> 1.10"}' >> mix.exs

  # 2. Install
  mix deps.get

  # 3. Create PromEx files (manual - use code above)
  mkdir -p lib/uptrack/prom_ex
  touch lib/uptrack/prom_ex.ex
  touch lib/uptrack/prom_ex/uptime_metrics.ex

  # 4. Start dev server
  mix phx.server

  # 5. Check metrics endpoint
  curl http://localhost:4000/metrics

  # 6. Start VictoriaMetrics (Docker)
  docker run -d -p 8428:8428 \
    -v victoria-data:/victoria-metrics-data \
    victoriametrics/victoria-metrics:latest \
    -storageDataPath=/victoria-metrics-data \
    -retentionPeriod=15M

  # 7. Configure scraping (see config above)

  ---
  💡 Best Practices for Uptrack

  1. Short scrape interval - 15-30s for real-time uptime monitoring
  2. Cardinality control - Don't use high-cardinality labels (like full URLs)
  3. Alert on metrics - Alert when uptrack_monitor_status == 0 for >5 minutes
  4. Monitor the monitor - Track oban_jobs_total{state="failure"} for check job failures
  5. SSL expiry alerts - Alert when uptrack_monitor_ssl_expiry_days < 30

  ---
  Summary: With this setup, Uptrack will automatically send comprehensive metrics to VictoriaMetrics, giving you full observability of your uptime monitoring
  system! 🎯
