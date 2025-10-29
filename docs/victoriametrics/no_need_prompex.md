
  ---
  🎯 Correct Understanding

  Two Separate Systems:

  ┌─────────────────────────────────────────────────────────┐
  │ 1. User-Facing Uptime Dashboard (Your Phoenix App)     │
  │    - Users see their uptime history (15 months)        │
  │    - Built with LiveView/React                          │
  │    - Queries: PostgreSQL + VictoriaMetrics             │
  └─────────────────────────────────────────────────────────┘
                           ↓
                    (stores metrics)
                           ↓
  ┌─────────────────────────────────────────────────────────┐
  │ 2. VictoriaMetrics (Backend Storage)                    │
  │    - Stores timeseries uptime data efficiently         │
  │    - 15-month retention                                 │
  │    - Query via HTTP API from Phoenix                    │
  └─────────────────────────────────────────────────────────┘
                           ↓
                    (optional, internal only)
                           ↓
  ┌─────────────────────────────────────────────────────────┐
  │ 3. Grafana (Internal Monitoring - Optional)            │
  │    - For YOU to monitor Uptrack's health               │
  │    - NOT for end users                                  │
  └─────────────────────────────────────────────────────────┘

  ---
  ✅ So You Want:

  1. ✅ Store uptime check data in VictoriaMetrics (efficient timeseries storage)
  2. ✅ Query VictoriaMetrics from Phoenix to show users their uptime history
  3. ✅ Custom metrics for uptime checks (response time, status, etc.)
  4. ❌ NOT using PromEx for end-user metrics (PromEx = internal monitoring only)

  ---
  📊 Simplified Architecture for End-User Metrics

  What You Actually Need:

  Phoenix App (Uptrack)
      ↓ (when uptime check runs)
      ↓
  Write metrics → VictoriaMetrics HTTP API
      ↓
  Store timeseries data (15 months)
      ↓ (when user views dashboard)
      ↓
  Query metrics ← VictoriaMetrics HTTP API
      ↓
  Display in LiveView/React dashboard

  No PromEx needed for this! PromEx is for internal monitoring only.

  ---
  🔧 Simple Custom Metrics Implementation

  Step 1: Write Metrics to VictoriaMetrics

  Option A: Direct Write (Simplest)

  # /repos/uptrack/lib/uptrack/metrics/writer.ex
  defmodule Uptrack.Metrics.Writer do
    @moduledoc """
    Write uptime check results directly to VictoriaMetrics
    """

    @vm_url "http://victoriametrics:8428/api/v1/import/prometheus"

    @doc """
    Write uptime check result to VictoriaMetrics
    """
    def write_check_result(monitor_id, result) do
      timestamp = System.os_time(:millisecond)

      metrics = [
        # Monitor status (1=up, 0=down)
        metric_line(
          "uptrack_monitor_status",
          if(result.success?, do: 1, else: 0),
          %{monitor_id: monitor_id},
          timestamp
        ),

        # Response time in milliseconds
        metric_line(
          "uptrack_monitor_response_time_ms",
          result.response_time,
          %{monitor_id: monitor_id},
          timestamp
        ),

        # HTTP status code
        metric_line(
          "uptrack_monitor_http_status",
          result.status_code || 0,
          %{monitor_id: monitor_id},
          timestamp
        )
      ]

      # Write all metrics in one request
      body = Enum.join(metrics, "\n")

      case Req.post(@vm_url, body: body, headers: [{"content-type", "text/plain"}]) do
        {:ok, %{status: 204}} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    defp metric_line(name, value, labels, timestamp) do
      labels_str =
        labels
        |> Enum.map(fn {k, v} -> ~s(#{k}="#{v}") end)
        |> Enum.join(",")

      "#{name}{#{labels_str}} #{value} #{timestamp}"
    end
  end

  Usage:

  # /repos/uptrack/lib/uptrack/monitors/checker.ex
  defmodule Uptrack.Monitors.Checker do
    alias Uptrack.Metrics.Writer

    def check_monitor(monitor) do
      start_time = System.monotonic_time()

      result = perform_http_check(monitor.url)

      duration = System.monotonic_time() - start_time
      response_time_ms = System.convert_time_unit(duration, :native, :millisecond)

      check_result = %{
        success?: result.success?,
        response_time: response_time_ms,
        status_code: result.status
      }

      # Write to VictoriaMetrics
      Writer.write_check_result(monitor.id, check_result)

      # Also save to PostgreSQL if needed
      save_check_to_db(monitor, check_result)

      check_result
    end
  end

  ---
  Step 2: Query Metrics from VictoriaMetrics

  # /repos/uptrack/lib/uptrack/metrics/reader.ex
  defmodule Uptrack.Metrics.Reader do
    @moduledoc """
    Query uptime metrics from VictoriaMetrics for user dashboards
    """

    @vm_url "http://victoriametrics:8428/api/v1/query_range"

    @doc """
    Get uptime percentage for a monitor over time range

    ## Example
        Reader.get_uptime_percentage(123, ~N[2024-01-01 00:00:00], ~N[2024-12-31 23:59:59])
        # => %{uptime_percent: 99.95, data_points: [...]}
    """
    def get_uptime_percentage(monitor_id, start_time, end_time) do
      query = """
      avg_over_time(uptrack_monitor_status{monitor_id="#{monitor_id}"}[5m])
      """

      params = %{
        query: query,
        start: datetime_to_unix(start_time),
        end: datetime_to_unix(end_time),
        step: "5m"  # 5-minute resolution
      }

      case Req.get(@vm_url, params: params) do
        {:ok, %{status: 200, body: body}} ->
          parse_uptime_response(body)

        {:error, reason} ->
          {:error, reason}
      end
    end

    @doc """
    Get response time data for a monitor
    """
    def get_response_times(monitor_id, start_time, end_time) do
      query = """
      uptrack_monitor_response_time_ms{monitor_id="#{monitor_id}"}
      """

      params = %{
        query: query,
        start: datetime_to_unix(start_time),
        end: datetime_to_unix(end_time),
        step: "1m"
      }

      case Req.get(@vm_url, params: params) do
        {:ok, %{status: 200, body: body}} ->
          parse_response_time_data(body)

        {:error, reason} ->
          {:error, reason}
      end
    end

    @doc """
    Get uptime statistics for a specific time range
    """
    def get_uptime_stats(monitor_id, start_time, end_time) do
      # Average uptime percentage
      uptime_query = """
      avg_over_time(uptrack_monitor_status{monitor_id="#{monitor_id}"}[#{range_duration(start_time, end_time)}])
      """

      # P95 response time
      p95_query = """
      quantile_over_time(0.95, uptrack_monitor_response_time_ms{monitor_id="#{monitor_id}"}[#{range_duration(start_time, end_time)}])
      """

      # Average response time
      avg_query = """
      avg_over_time(uptrack_monitor_response_time_ms{monitor_id="#{monitor_id}"}[#{range_duration(start_time, end_time)}])
      """

      # Make queries in parallel
      tasks = [
        Task.async(fn -> query_instant(@vm_url <> "_instant", uptime_query) end),
        Task.async(fn -> query_instant(@vm_url <> "_instant", p95_query) end),
        Task.async(fn -> query_instant(@vm_url <> "_instant", avg_query) end)
      ]

      [uptime, p95, avg] = Task.await_many(tasks)

      %{
        uptime_percent: uptime * 100,
        p95_response_time: p95,
        avg_response_time: avg
      }
    end

    defp parse_uptime_response(%{"data" => %{"result" => [%{"values" => values}]}}) do
      data_points =
        Enum.map(values, fn [timestamp, value] ->
          %{
            timestamp: unix_to_datetime(timestamp),
            uptime: String.to_float(value)
          }
        end)

      uptime_percent =
        data_points
        |> Enum.map(& &1.uptime)
        |> Enum.sum()
        |> Kernel./(length(data_points))
        |> Kernel.*(100)

      {:ok, %{uptime_percent: uptime_percent, data_points: data_points}}
    end

    defp parse_response_time_data(%{"data" => %{"result" => [%{"values" => values}]}}) do
      data_points =
        Enum.map(values, fn [timestamp, value] ->
          %{
            timestamp: unix_to_datetime(timestamp),
            response_time: String.to_float(value)
          }
        end)

      {:ok, data_points}
    end

    defp query_instant(url, query) do
      case Req.get(url, params: %{query: query}) do
        {:ok, %{body: %{"data" => %{"result" => [%{"value" => [_ts, value]}]}}}} ->
          String.to_float(value)

        _ ->
          0.0
      end
    end

    defp datetime_to_unix(datetime) do
      DateTime.from_naive!(datetime, "Etc/UTC") |> DateTime.to_unix()
    end

    defp unix_to_datetime(unix) when is_integer(unix) do
      DateTime.from_unix!(unix) |> DateTime.to_naive()
    end
    defp unix_to_datetime(unix) when is_float(unix) do
      DateTime.from_unix!(trunc(unix)) |> DateTime.to_naive()
    end

    defp range_duration(start_time, end_time) do
      diff_seconds = NaiveDateTime.diff(end_time, start_time)
      "#{diff_seconds}s"
    end
  end

  ---
  Step 3: Use in LiveView for User Dashboard

  # /repos/uptrack/lib/uptrack_web/live/monitor_live/show.ex
  defmodule UptrackWeb.MonitorLive.Show do
    use UptrackWeb, :live_view

    alias Uptrack.Metrics.Reader
    alias Uptrack.Monitors

    @impl true
    def mount(%{"id" => id}, _session, socket) do
      monitor = Monitors.get_monitor!(id)

      # Default to last 24 hours
      end_time = NaiveDateTime.utc_now()
      start_time = NaiveDateTime.add(end_time, -24 * 3600)

      socket =
        socket
        |> assign(:monitor, monitor)
        |> assign(:start_time, start_time)
        |> assign(:end_time, end_time)
        |> assign(:loading, true)
        |> load_metrics()

      {:ok, socket}
    end

    @impl true
    def handle_event("change_timerange", %{"range" => range}, socket) do
      {start_time, end_time} = calculate_timerange(range)

      socket =
        socket
        |> assign(:start_time, start_time)
        |> assign(:end_time, end_time)
        |> assign(:loading, true)
        |> load_metrics()

      {:noreply, socket}
    end

    defp load_metrics(socket) do
      monitor_id = socket.assigns.monitor.id
      start_time = socket.assigns.start_time
      end_time = socket.assigns.end_time

      # Load metrics from VictoriaMetrics
      case Reader.get_uptime_stats(monitor_id, start_time, end_time) do
        {:ok, stats} ->
          # Also load time-series data for chart
          {:ok, uptime_data} = Reader.get_uptime_percentage(monitor_id, start_time, end_time)
          {:ok, response_times} = Reader.get_response_times(monitor_id, start_time, end_time)

          socket
          |> assign(:loading, false)
          |> assign(:stats, stats)
          |> assign(:uptime_data, uptime_data)
          |> assign(:response_times, response_times)

        {:error, _reason} ->
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to load metrics")
      end
    end

    defp calculate_timerange("24h") do
      end_time = NaiveDateTime.utc_now()
      start_time = NaiveDateTime.add(end_time, -24 * 3600)
      {start_time, end_time}
    end

    defp calculate_timerange("7d") do
      end_time = NaiveDateTime.utc_now()
      start_time = NaiveDateTime.add(end_time, -7 * 24 * 3600)
      {start_time, end_time}
    end

    defp calculate_timerange("30d") do
      end_time = NaiveDateTime.utc_now()
      start_time = NaiveDateTime.add(end_time, -30 * 24 * 3600)
      {start_time, end_time}
    end

    defp calculate_timerange("15m") do
      end_time = NaiveDateTime.utc_now()
      start_time = NaiveDateTime.add(end_time, -15 * 30 * 24 * 3600)
      {start_time, end_time}
    end
  end

  Template:

  <!-- /repos/uptrack/lib/uptrack_web/live/monitor_live/show.html.heex -->
  <div class="monitor-dashboard">
    <h1><%= @monitor.name %></h1>

    <!-- Timerange selector -->
    <div class="timerange-selector">
      <button phx-click="change_timerange" phx-value-range="24h">24 Hours</button>
      <button phx-click="change_timerange" phx-value-range="7d">7 Days</button>
      <button phx-click="change_timerange" phx-value-range="30d">30 Days</button>
      <button phx-click="change_timerange" phx-value-range="15m">15 Months</button>
    </div>

    <%= if @loading do %>
      <p>Loading metrics...</p>
    <% else %>
      <!-- Stats cards -->
      <div class="stats-grid">
        <div class="stat-card">
          <h3>Uptime</h3>
          <p class="stat-value"><%= Float.round(@stats.uptime_percent, 2) %>%</p>
        </div>

        <div class="stat-card">
          <h3>Avg Response Time</h3>
          <p class="stat-value"><%= round(@stats.avg_response_time) %>ms</p>
        </div>

        <div class="stat-card">
          <h3>P95 Response Time</h3>
          <p class="stat-value"><%= round(@stats.p95_response_time) %>ms</p>
        </div>
      </div>

      <!-- Charts (use Chart.js, D3.js, or similar) -->
      <div class="charts">
        <div id="uptime-chart" phx-hook="UptimeChart" data-points={Jason.encode!(@uptime_data.data_points)}></div>
        <div id="response-time-chart" phx-hook="ResponseTimeChart" data-points={Jason.encode!(@response_times)}></div>
      </div>
    <% end %>
  </div>

  ---
  📝 Summary: Is It Hard?

  ❌ NO, it's NOT hard! Here's why:

  1. Writing metrics: Just HTTP POST with simple text format
  # One line:
  "uptrack_monitor_status{monitor_id=\"123\"} 1 1706400000000"
  2. Reading metrics: Just HTTP GET with PromQL query
  # Simple query:
  Req.get(url, params: %{query: "uptrack_monitor_status{monitor_id=\"123\"}"})
  3. No complex setup: No PromEx, no Prometheus, just HTTP API

  ---
  ⚡ Quick Start (Minimal Setup)

  # 1. Write module (2 functions)
  defmodule Uptrack.VM do
    @url "http://vm:8428"

    def write(name, value, labels) do
      metric = "#{name}{#{format_labels(labels)}} #{value} #{:os.system_time(:millisecond)}"
      Req.post("#{@url}/api/v1/import/prometheus", body: metric)
    end

    def query(promql, start_time, end_time) do
      Req.get("#{@url}/api/v1/query_range", params: %{
        query: promql,
        start: to_unix(start_time),
        end: to_unix(end_time),
        step: "1m"
      })
    end

    defp format_labels(labels) do
      Enum.map_join(labels, ",", fn {k, v} -> ~s(#{k}="#{v}") end)
    end

    defp to_unix(dt), do: DateTime.from_naive!(dt, "Etc/UTC") |> DateTime.to_unix()
  end

  # 2. Use it
  VM.write("uptrack_status", 1, %{monitor_id: 123})
  VM.query("uptrack_status{monitor_id=\"123\"}", start, end)

  That's it! 🎉

  ---
  💰 Storage Efficiency

  VictoriaMetrics is extremely efficient:

  | Data Type                 | Storage Size       |
  |---------------------------|--------------------|
  | 1 uptime check            | ~20 bytes          |
  | 1 million checks          | ~20 MB             |
  | 15 months (1 check/min)   | ~20 MB per monitor |
  | 1000 monitors × 15 months | ~20 GB             |

  Your 150GB VictoriaMetrics can store millions of monitors! 🚀

  ---
  Bottom line: Building custom metrics is easy - just 2 HTTP endpoints (write/read). No complex setup needed! Focus on your user dashboard, VictoriaMetrics
  handles storage efficiently. 🎯
