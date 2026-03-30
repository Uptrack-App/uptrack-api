defmodule UptrackWeb.Api.AnalyticsController do
  @moduledoc """
  API endpoints for dashboard analytics data.

  Provides aggregated statistics, charts, and trends for monitors.
  """

  use UptrackWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Uptrack.Monitoring
  alias Uptrack.Metrics.{Reader, Retention}
  alias Uptrack.Cache
  alias UptrackWeb.Schemas.Analytics

  tags ["Analytics"]

  operation :dashboard,
    summary: "Get dashboard overview",
    description: """
    Returns dashboard statistics and overview data for the current organization.
    Includes monitor counts, incident counts, and overall uptime.
    """,
    security: [%{"session" => []}],
    parameters: [
      days: [
        in: :query,
        description: "Number of days to include in calculations",
        schema: %OpenApiSpex.Schema{type: :integer, default: 30, minimum: 1, maximum: 365}
      ]
    ],
    responses: [
      ok: {"Dashboard overview", "application/json", Analytics.DashboardResponse},
      unauthorized: {"Unauthorized", "application/json", UptrackWeb.Schemas.Heartbeat.ErrorResponse}
    ]

  operation :monitor_stats,
    summary: "Get monitor analytics",
    description: """
    Returns detailed analytics for a specific monitor including:
    - Uptime chart data (daily breakdown)
    - Response time trends
    - Incident statistics
    """,
    security: [%{"session" => []}],
    parameters: [
      monitor_id: [in: :path, description: "Monitor ID", schema: %OpenApiSpex.Schema{type: :integer}],
      days: [
        in: :query,
        description: "Number of days to include",
        schema: %OpenApiSpex.Schema{type: :integer, default: 30, minimum: 1, maximum: 365}
      ]
    ],
    responses: [
      ok: {"Monitor analytics", "application/json", Analytics.MonitorAnalyticsResponse},
      not_found: {"Monitor not found", "application/json", UptrackWeb.Schemas.Heartbeat.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", UptrackWeb.Schemas.Heartbeat.ErrorResponse}
    ]

  operation :organization_trends,
    summary: "Get organization-wide trends",
    description: """
    Returns aggregated analytics across all monitors for the organization.
    Includes overall uptime trends and incident frequency.
    """,
    security: [%{"session" => []}],
    parameters: [
      days: [
        in: :query,
        description: "Number of days to include",
        schema: %OpenApiSpex.Schema{type: :integer, default: 30, minimum: 1, maximum: 365}
      ]
    ],
    responses: [
      ok: {"Organization trends", "application/json", Analytics.OrganizationTrendsResponse},
      unauthorized: {"Unauthorized", "application/json", UptrackWeb.Schemas.Heartbeat.ErrorResponse}
    ]

  @doc """
  GET /api/analytics/dashboard

  Returns dashboard overview statistics.
  """
  def dashboard(conn, params) do
    %{current_organization: org} = conn.assigns
    days = parse_days(params)

    result =
      Cache.fetch(Cache.dashboard_analytics_key(org.id, days), [ttl: Cache.ttl_medium()], fn ->
        stats = Monitoring.get_dashboard_stats(org.id)
        overall_uptime = Monitoring.get_organization_overall_uptime(org.id, days)
        org_trends = get_organization_uptime_trends(org.id, days)

        %{
          stats: stats,
          overall_uptime: overall_uptime,
          uptime_trend: org_trends,
          period_days: days
        }
      end)

    json(conn, result)
  end

  @doc """
  GET /api/analytics/monitors/:monitor_id

  Returns detailed analytics for a specific monitor.
  """
  def monitor_stats(conn, %{"monitor_id" => monitor_id} = params) do
    %{current_organization: org} = conn.assigns
    days = parse_days(params)

    # Verify the monitor belongs to this organization
    case Monitoring.get_organization_monitor!(org.id, monitor_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Monitor not found"})

      _monitor ->
        plan = org.plan
        now = DateTime.utc_now()
        requested_start = DateTime.add(now, -days * 86400, :second)
        {start_time, end_time} = Retention.clamp_range(requested_start, now, plan)
        clamped_days = div(DateTime.diff(end_time, start_time, :second), 86400) |> max(1)
        step = Retention.step_for_days(days)

        result =
          Cache.fetch(Cache.monitor_analytics_key(monitor_id, days), [ttl: Cache.ttl_medium()], fn ->
            # Try VictoriaMetrics first, fall back to PostgreSQL
            {response_times, percentiles} = fetch_response_data(monitor_id, start_time, end_time, step)
            uptime_chart = fetch_uptime_chart(monitor_id, start_time, end_time, clamped_days)
            incident_stats = Monitoring.get_incident_stats(monitor_id, clamped_days)

            %{
              monitor_id: monitor_id,
              period_days: clamped_days,
              uptime_chart: uptime_chart,
              response_times: response_times,
              percentiles: percentiles,
              incident_stats: incident_stats
            }
          end)

        json(conn, result)
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Monitor not found"})
  end

  @doc """
  GET /api/analytics/organization/trends

  Returns organization-wide trend data.
  """
  def organization_trends(conn, params) do
    %{current_organization: org} = conn.assigns
    days = parse_days(params)

    result =
      Cache.fetch(Cache.org_trends_key(org.id, days), [ttl: Cache.ttl_medium()], fn ->
        overall_uptime = Monitoring.get_organization_overall_uptime(org.id, days)
        uptime_trends = get_organization_uptime_trends(org.id, days)
        incident_frequency = get_incident_frequency(org.id, days)
        top_offenders = get_top_offenders(org.id, days)

        %{
          period_days: days,
          overall_uptime: overall_uptime,
          uptime_trends: uptime_trends,
          incident_frequency: incident_frequency,
          top_offenders: top_offenders
        }
      end)

    json(conn, result)
  end

  # Private helpers — VM Reader with PostgreSQL fallback

  defp fetch_response_data(monitor_id, start_time, end_time, step) do
    case Reader.get_response_times(monitor_id, start_time, end_time, step) do
      {:ok, []} ->
        # VM has no data — fall back to PostgreSQL
        days = div(DateTime.diff(end_time, start_time, :second), 86400) |> max(1)
        pg_data = Monitoring.get_response_time_trends(monitor_id, days)
        {pg_data, %{p50: 0.0, p95: 0.0, p99: 0.0}}

      {:ok, points} ->
        formatted =
          Enum.map(points, fn {ts, val} ->
            %{timestamp: ts, response_time: Float.round(val, 2)}
          end)

        percentiles =
          case Reader.get_response_time_percentiles(monitor_id, start_time, end_time) do
            {:ok, p} -> p
            _ -> %{p50: 0.0, p95: 0.0, p99: 0.0}
          end

        {formatted, percentiles}

      {:error, _} ->
        days = div(DateTime.diff(end_time, start_time, :second), 86400) |> max(1)
        pg_data = Monitoring.get_response_time_trends(monitor_id, days)
        {pg_data, %{p50: 0.0, p95: 0.0, p99: 0.0}}
    end
  end

  defp fetch_uptime_chart(monitor_id, start_time, end_time, days) do
    case Reader.get_daily_uptime(monitor_id, start_time, end_time) do
      {:ok, []} ->
        Monitoring.get_uptime_chart_data(monitor_id, days)

      {:ok, points} ->
        points

      {:error, _} ->
        Monitoring.get_uptime_chart_data(monitor_id, days)
    end
  end

  defp parse_days(%{"days" => days}) when is_binary(days) do
    case Integer.parse(days) do
      {d, _} when d >= 1 and d <= 365 -> d
      _ -> 30
    end
  end

  defp parse_days(%{"days" => days}) when is_integer(days) and days >= 1 and days <= 365, do: days
  defp parse_days(_), do: 30

  defp get_organization_uptime_trends(organization_id, days) do
    import Ecto.Query

    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from mc in Uptrack.Monitoring.MonitorCheck,
        join: m in Uptrack.Monitoring.Monitor,
        on: mc.monitor_id == m.id,
        where: m.organization_id == ^organization_id and mc.checked_at >= ^cutoff_date,
        select: %{
          date: fragment("DATE(?)", mc.checked_at),
          total: count(mc.id),
          up: count(mc.id) |> filter(mc.status == "up")
        },
        group_by: fragment("DATE(?)", mc.checked_at),
        order_by: [asc: fragment("DATE(?)", mc.checked_at)]

    Uptrack.AppRepo.all(query)
    |> Enum.map(fn stat ->
      %{
        date: stat.date,
        uptime:
          if(stat.total > 0, do: Float.round(stat.up / stat.total * 100, 2), else: 100.0),
        total_checks: stat.total
      }
    end)
  end

  defp get_incident_frequency(organization_id, days) do
    import Ecto.Query

    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from i in Uptrack.Monitoring.Incident,
        where: i.organization_id == ^organization_id and i.started_at >= ^cutoff_date,
        select: %{
          date: fragment("DATE(?)", i.started_at),
          count: count(i.id)
        },
        group_by: fragment("DATE(?)", i.started_at),
        order_by: [asc: fragment("DATE(?)", i.started_at)]

    Uptrack.AppRepo.all(query)
  end

  defp get_top_offenders(organization_id, days) do
    import Ecto.Query

    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from i in Uptrack.Monitoring.Incident,
        join: m in Uptrack.Monitoring.Monitor,
        on: i.monitor_id == m.id,
        where: m.organization_id == ^organization_id and i.started_at >= ^cutoff_date,
        select: %{
          monitor_id: m.id,
          monitor_name: m.name,
          incident_count: count(i.id),
          total_downtime:
            sum(
              fragment(
                "COALESCE(?, EXTRACT(EPOCH FROM NOW() - ?))",
                i.duration,
                i.started_at
              )
            )
        },
        group_by: [m.id, m.name],
        order_by: [desc: count(i.id)],
        limit: 5

    Uptrack.AppRepo.all(query)
    |> Enum.map(fn stat ->
      %{
        monitor_id: stat.monitor_id,
        monitor_name: stat.monitor_name,
        incident_count: stat.incident_count,
        total_downtime_seconds: stat.total_downtime |> Decimal.to_float() |> round()
      }
    end)
  end
end
