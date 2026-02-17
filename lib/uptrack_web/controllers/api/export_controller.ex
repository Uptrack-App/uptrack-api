defmodule UptrackWeb.Api.ExportController do
  use UptrackWeb, :controller

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{MonitorCheck, Incident}

  import Ecto.Query

  @doc """
  Exports monitor data as CSV.

  GET /api/analytics/export?format=csv&monitor_id=X&start=DATE&end=DATE

  Parameters:
    - format: "csv" (required)
    - monitor_id: optional, specific monitor. Without it, exports all monitors.
    - start: ISO 8601 date (default: 30 days ago)
    - end: ISO 8601 date (default: today)
  """
  def export(conn, params) do
    org = conn.assigns.current_organization

    {start_date, end_date} = parse_date_range(params)

    case params["monitor_id"] do
      nil ->
        # Org-wide export: one row per monitor per day
        monitors = Monitoring.list_monitors(org.id)
        csv = build_org_csv(monitors, start_date, end_date)
        send_csv(conn, csv, "uptrack-export-#{Date.to_iso8601(start_date)}-#{Date.to_iso8601(end_date)}.csv")

      monitor_id ->
        case Monitoring.get_organization_monitor(org.id, monitor_id) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: %{message: "Monitor not found"}})

          monitor ->
            csv = build_monitor_csv(monitor, start_date, end_date)
            send_csv(conn, csv, "#{slugify(monitor.name)}-export-#{Date.to_iso8601(start_date)}-#{Date.to_iso8601(end_date)}.csv")
        end
    end
  end

  # --------------------------------------------------------------------------
  # CSV builders
  # --------------------------------------------------------------------------

  defp build_monitor_csv(monitor, start_date, end_date) do
    daily_stats = get_daily_stats(monitor.id, start_date, end_date)
    daily_incidents = get_daily_incidents(monitor.id, start_date, end_date)

    header = "date,uptime_pct,avg_response_ms,p95_response_ms,p99_response_ms,total_checks,failed_checks,incidents\n"

    rows =
      Date.range(start_date, end_date)
      |> Enum.map(fn date ->
        stats = Map.get(daily_stats, date, %{total: 0, up: 0, avg_rt: 0, p95_rt: 0, p99_rt: 0})
        incidents = Map.get(daily_incidents, date, 0)

        uptime = if stats.total > 0, do: Float.round(stats.up / stats.total * 100, 2), else: 100.0
        failed = stats.total - stats.up

        "#{date},#{uptime},#{round_or_zero(stats.avg_rt)},#{round_or_zero(stats.p95_rt)},#{round_or_zero(stats.p99_rt)},#{stats.total},#{failed},#{incidents}"
      end)
      |> Enum.join("\n")

    header <> rows <> "\n"
  end

  defp build_org_csv(monitors, start_date, end_date) do
    header = "date,monitor_name,monitor_url,uptime_pct,avg_response_ms,total_checks,failed_checks,incidents\n"

    rows =
      for monitor <- monitors,
          date <- Date.range(start_date, end_date) do
        {monitor, date}
      end
      |> Enum.chunk_every(50)
      |> Enum.flat_map(fn chunk ->
        # Process in batches to avoid excessive queries
        monitor_ids = chunk |> Enum.map(fn {m, _} -> m.id end) |> Enum.uniq()

        all_stats =
          Enum.reduce(monitor_ids, %{}, fn mid, acc ->
            stats = get_daily_stats(mid, start_date, end_date)
            Map.put(acc, mid, stats)
          end)

        all_incidents =
          Enum.reduce(monitor_ids, %{}, fn mid, acc ->
            incidents = get_daily_incidents(mid, start_date, end_date)
            Map.put(acc, mid, incidents)
          end)

        Enum.map(chunk, fn {monitor, date} ->
          stats =
            all_stats
            |> Map.get(monitor.id, %{})
            |> Map.get(date, %{total: 0, up: 0, avg_rt: 0})

          incidents =
            all_incidents
            |> Map.get(monitor.id, %{})
            |> Map.get(date, 0)

          uptime = if stats.total > 0, do: Float.round(stats.up / stats.total * 100, 2), else: 100.0
          failed = stats.total - stats.up

          "#{date},#{csv_escape(monitor.name)},#{csv_escape(monitor.url)},#{uptime},#{round_or_zero(stats.avg_rt)},#{stats.total},#{failed},#{incidents}"
        end)
      end)
      |> Enum.join("\n")

    header <> rows <> "\n"
  end

  # --------------------------------------------------------------------------
  # Data queries
  # --------------------------------------------------------------------------

  defp get_daily_stats(monitor_id, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00])
    end_dt = DateTime.new!(end_date, ~T[23:59:59])

    query =
      from mc in MonitorCheck,
        where:
          mc.monitor_id == ^monitor_id and
            mc.checked_at >= ^start_dt and
            mc.checked_at <= ^end_dt,
        select: %{
          date: fragment("DATE(?)", mc.checked_at),
          total: count(mc.id),
          up: filter(count(mc.id), mc.status == "up"),
          avg_rt: avg(mc.response_time),
          p95_rt: fragment("percentile_cont(0.95) WITHIN GROUP (ORDER BY ?)", mc.response_time),
          p99_rt: fragment("percentile_cont(0.99) WITHIN GROUP (ORDER BY ?)", mc.response_time)
        },
        group_by: fragment("DATE(?)", mc.checked_at)

    Uptrack.AppRepo.all(query)
    |> Map.new(fn row ->
      {row.date, %{
        total: row.total,
        up: row.up,
        avg_rt: row.avg_rt,
        p95_rt: row.p95_rt,
        p99_rt: row.p99_rt
      }}
    end)
  end

  defp get_daily_incidents(monitor_id, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00])
    end_dt = DateTime.new!(end_date, ~T[23:59:59])

    query =
      from i in Incident,
        where:
          i.monitor_id == ^monitor_id and
            i.started_at >= ^start_dt and
            i.started_at <= ^end_dt,
        select: %{
          date: fragment("DATE(?)", i.started_at),
          count: count(i.id)
        },
        group_by: fragment("DATE(?)", i.started_at)

    Uptrack.AppRepo.all(query)
    |> Map.new(fn row -> {row.date, row.count} end)
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp parse_date_range(params) do
    end_date =
      case params["end"] do
        nil -> Date.utc_today()
        str -> Date.from_iso8601!(str)
      end

    start_date =
      case params["start"] do
        nil -> Date.add(end_date, -30)
        str -> Date.from_iso8601!(str)
      end

    {start_date, end_date}
  end

  defp send_csv(conn, csv_content, filename) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, csv_content)
  end

  defp csv_escape(str) when is_binary(str) do
    if String.contains?(str, [",", "\"", "\n"]) do
      "\"" <> String.replace(str, "\"", "\"\"") <> "\""
    else
      str
    end
  end

  defp csv_escape(val), do: to_string(val)

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp round_or_zero(nil), do: 0
  defp round_or_zero(%Decimal{} = d), do: Decimal.to_float(d) |> Float.round(2)
  defp round_or_zero(val) when is_float(val), do: Float.round(val, 2)
  defp round_or_zero(val) when is_number(val), do: val
end
