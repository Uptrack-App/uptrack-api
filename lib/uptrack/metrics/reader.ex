defmodule Uptrack.Metrics.Reader do
  @moduledoc """
  Reads uptime metrics from VictoriaMetrics via the vmselect query API.

  Used to display historical uptime data, response time charts, etc.
  """

  require Logger

  @doc """
  Queries uptime percentage for a monitor over the last N days.

  Returns `{:ok, float}` between 0.0 and 100.0.
  """
  def get_uptime_percentage(monitor_id, days \\ 30) do
    now = DateTime.utc_now()
    range = "#{days * 24}h"
    query = "avg_over_time(uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}[#{range}])"

    case query_instant(query, now) do
      {:ok, value} -> {:ok, Float.round(value * 100, 2)}
      {:error, _} -> {:ok, 100.0}
    end
  end

  @doc """
  Returns uptime chart data for a monitor over the last N days.

  Returns `{:ok, [%{date: Date.t(), uptime: float(), total: integer()}]}` with gaps
  filled as 100% uptime.
  """
  def get_uptime_chart_data(monitor_id, days \\ 30) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)

    case get_daily_uptime(monitor_id, start_time, now) do
      {:ok, points} ->
        by_date = Map.new(points, &{&1.date, &1})
        start_date = Date.add(Date.utc_today(), -days)

        chart =
          Enum.map(0..(days - 1), fn offset ->
            date = Date.add(start_date, offset)
            case Map.get(by_date, date) do
              nil -> %{date: date, uptime: 100.0, total: 0}
              point -> Map.put(point, :total, 1)
            end
          end)

        {:ok, chart}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns daily stats for a monitor between two dates, used by the export endpoint.

  Returns `{:ok, %{Date.t() => %{total, up, avg_rt, p95_rt, p99_rt}}}`.
  """
  def get_daily_stats(monitor_id, start_date, end_date) do
    start_time = DateTime.new!(start_date, ~T[00:00:00])
    end_time = DateTime.new!(end_date, ~T[23:59:59])

    status_q = "avg_over_time(uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}[1d])"
    count_q = "count_over_time(uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}[1d])"
    avg_rt_q = "avg_over_time(uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}[1d])"
    p95_q = "quantile_over_time(0.95, uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}[1d])"
    p99_q = "quantile_over_time(0.99, uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}[1d])"

    with {:ok, status_r} <- query_range(status_q, start_time, end_time, "1d"),
         {:ok, count_r} <- query_range(count_q, start_time, end_time, "1d"),
         {:ok, avg_rt_r} <- query_range(avg_rt_q, start_time, end_time, "1d"),
         {:ok, p95_r} <- query_range(p95_q, start_time, end_time, "1d"),
         {:ok, p99_r} <- query_range(p99_q, start_time, end_time, "1d") do
      statuses = extract_daily_values(status_r)
      counts = extract_daily_values(count_r)
      avg_rts = extract_daily_values(avg_rt_r)
      p95s = extract_daily_values(p95_r)
      p99s = extract_daily_values(p99_r)

      result =
        Map.new(statuses, fn {date, uptime_frac} ->
          total = Map.get(counts, date, 0) |> trunc()
          up = round(uptime_frac * total)
          {date, %{total: total, up: up, avg_rt: Map.get(avg_rts, date), p95_rt: Map.get(p95s, date), p99_rt: Map.get(p99s, date)}}
        end)

      {:ok, result}
    end
  end

  @doc """
  Returns per-region latest response times for a monitor.

  Returns `{:ok, %{"europe" => 74, "us" => 120, ...}}`.
  """
  def get_region_response_times(monitor_id) do
    case vmselect_url() do
      nil ->
        {:ok, %{}}

      url ->
        query_url = "#{url}/api/v1/query"
        query = "uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}"
        params = %{query: query, time: DateTime.to_unix(DateTime.utc_now())}

        case Req.get(query_url, params: params) do
          {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => results}}}} ->
            region_map =
              Map.new(results, fn %{"metric" => m, "value" => [_ts, val]} ->
                {m["region"] || "unknown", parse_float(val) |> trunc()}
              end)

            {:ok, region_map}

          _ ->
            {:ok, %{}}
        end
    end
  rescue
    _ -> {:ok, %{}}
  end

  @doc """
  Returns daily org-level uptime trend averaged across all monitors for the org.

  Returns `{:ok, [%{date: Date.t(), uptime: float(), total_checks: integer()}]}`.
  """
  def get_org_uptime_trends(organization_id, days) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)
    query = "avg(avg_over_time(uptrack_monitor_status{org_id=\"#{organization_id}\"}[1d]))"

    case query_range(query, start_time, now, "1d") do
      {:ok, results} ->
        points =
          results
          |> List.first(%{})
          |> Map.get("values", [])
          |> Enum.map(fn [ts, val] ->
            %{
              date: ts |> trunc() |> DateTime.from_unix!() |> DateTime.to_date(),
              uptime: parse_float(val) * 100 |> Float.round(2),
              total_checks: 0
            }
          end)

        {:ok, points}

      {:error, _} ->
        {:ok, []}
    end
  end

  @doc """
  Queries response time series for a monitor.

  Returns a list of `{unix_timestamp, response_time_ms}` tuples.
  """
  def get_response_times(monitor_id, start_time, end_time, step \\ "5m") do
    query = "uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}"

    case query_range(query, start_time, end_time, step) do
      {:ok, results} ->
        points =
          results
          |> List.first(%{})
          |> Map.get("values", [])
          |> Enum.map(fn [ts, val] -> {ts, parse_float(val)} end)

        {:ok, points}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_range(query, start_time, end_time, step) do
    case vmselect_url() do
      nil ->
        {:ok, []}

      url ->
        query_url = "#{url}/api/v1/query_range"

        params = %{
          query: query,
          start: DateTime.to_unix(start_time),
          end: DateTime.to_unix(end_time),
          step: step
        }

        case Req.get(query_url, params: params) do
          {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => results}}}} ->
            {:ok, results}

          {:ok, %{status: 200, body: %{"status" => "error", "error" => error}}} ->
            Logger.warning("VictoriaMetrics query error: #{error}")
            {:error, error}

          {:ok, %{status: status}} ->
            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.warning("VictoriaMetrics query failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  rescue
    e ->
      Logger.warning("VictoriaMetrics query exception: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc """
  Queries daily uptime for a monitor over a time range.

  Returns a list of `%{date: Date.t(), uptime: float()}` maps.
  Uses `avg_over_time(status[1d])` with step=1d for daily granularity.
  """
  def get_daily_uptime(monitor_id, start_time, end_time) do
    query = "avg_over_time(uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}[1d])"

    case query_range(query, start_time, end_time, "1d") do
      {:ok, results} ->
        points =
          results
          |> List.first(%{})
          |> Map.get("values", [])
          |> Enum.map(fn [ts, val] ->
            %{
              date: ts |> trunc() |> DateTime.from_unix!() |> DateTime.to_date(),
              uptime: parse_float(val) * 100 |> Float.round(2)
            }
          end)

        {:ok, points}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns daily response time aggregates (avg/min/max/total) for a monitor.

  Returns a list of `%{date, avg, min, max, total_checks}` maps ordered by date.
  This is the VictoriaMetrics replacement for the Postgres get_response_time_trends query.
  """
  def get_response_time_trends(monitor_id, days \\ 30) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)
    base = "uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}"

    with {:ok, avg_r} <- query_range("avg_over_time(#{base}[1d])", start_time, now, "1d"),
         {:ok, min_r} <- query_range("min_over_time(#{base}[1d])", start_time, now, "1d"),
         {:ok, max_r} <- query_range("max_over_time(#{base}[1d])", start_time, now, "1d"),
         {:ok, cnt_r} <- query_range("count_over_time(#{base}[1d])", start_time, now, "1d") do
      avgs = extract_daily_values(avg_r)
      mins = extract_daily_values(min_r)
      maxs = extract_daily_values(max_r)
      cnts = extract_daily_values(cnt_r)

      result =
        avgs
        |> Enum.sort_by(fn {date, _} -> date end)
        |> Enum.map(fn {date, avg} ->
          %{
            date: date,
            avg: Float.round(avg, 2),
            min: Map.get(mins, date, 0) |> trunc(),
            max: Map.get(maxs, date, 0) |> trunc(),
            total_checks: Map.get(cnts, date, 0) |> trunc()
          }
        end)

      result
    else
      {:error, _} -> []
    end
  end

  @doc """
  Queries response time percentiles for a monitor.

  Returns `{:ok, %{p50: float, p95: float, p99: float}}` for the given period.
  """
  def get_response_time_percentiles(monitor_id, start_time, end_time) do
    base = "uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}"

    results =
      for {label, quantile} <- [p50: "0.5", p95: "0.95", p99: "0.99"] do
        query = "quantile_over_time(#{quantile}, #{base}[#{range_duration(start_time, end_time)}])"

        case query_instant(query, end_time) do
          {:ok, value} -> {label, value}
          {:error, _} -> {label, 0.0}
        end
      end

    {:ok, Map.new(results)}
  end

  @doc """
  Gets latest check status for multiple monitors in a single query.

  Returns a map of monitor_id => %{status, response_time, checked_at}.
  """
  def get_latest_checks_batch(monitor_ids) when is_list(monitor_ids) do
    case vmselect_url() do
      nil -> {:ok, %{}}
      _url ->
        # Query all monitor statuses at once
        status_query = "uptrack_monitor_status"
        rt_query = "uptrack_monitor_response_time_ms"
        now = DateTime.utc_now()

        with {:ok, status_results} <- query_instant(status_query, now, :multi),
             {:ok, rt_results} <- query_instant(rt_query, now, :multi) do
          id_set = MapSet.new(monitor_ids, &to_string/1)

          statuses = extract_instant_by_monitor(status_results, id_set)
          response_times = extract_instant_by_monitor(rt_results, id_set)

          result =
            Map.new(statuses, fn {mid, {ts, val}} ->
              rt = case Map.get(response_times, mid) do
                {_, v} -> trunc(v)
                nil -> 0
              end

              {mid, %{
                status: if(val >= 0.5, do: "up", else: "down"),
                response_time: rt,
                checked_at: DateTime.from_unix!(trunc(ts))
              }}
            end)

          {:ok, result}
        end
    end
  end

  defp extract_instant_by_monitor(results, id_set) do
    results
    |> Enum.filter(fn %{"metric" => m} -> MapSet.member?(id_set, m["monitor_id"]) end)
    |> Map.new(fn %{"metric" => m, "value" => [ts, val]} ->
      {m["monitor_id"], {ts, parse_float(val)}}
    end)
  end

  defp query_instant(query, time, :multi) do
    case vmselect_url() do
      nil -> {:ok, []}
      url ->
        query_url = "#{url}/api/v1/query"
        params = %{query: query, time: DateTime.to_unix(time)}

        case Req.get(query_url, params: params) do
          {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => results}}}} ->
            {:ok, results}
          _ ->
            {:ok, []}
        end
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Queries recent check data points for a monitor.

  Returns a list of check-like maps for display in the recent checks table.
  """
  def get_recent_checks(monitor_id, limit \\ 20) do
    now = DateTime.utc_now()
    # Look back far enough to find `limit` data points at 30s intervals
    start_time = DateTime.add(now, -limit * 60, :second)

    status_query = "uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}"
    rt_query = "uptrack_monitor_response_time_ms{monitor_id=\"#{monitor_id}\"}"
    http_query = "uptrack_monitor_http_status{monitor_id=\"#{monitor_id}\"}"

    with {:ok, status_points} <- query_range(status_query, start_time, now, "30s"),
         {:ok, rt_points} <- query_range(rt_query, start_time, now, "30s"),
         {:ok, http_points} <- query_range(http_query, start_time, now, "30s") do
      statuses = extract_time_values(status_points)
      response_times = extract_time_values(rt_points)
      http_statuses = extract_time_values(http_points)

      checks =
        statuses
        |> Enum.map(fn {ts, status_val} ->
          %{
            status: if(status_val >= 0.5, do: "up", else: "down"),
            response_time: Map.get(response_times, ts, 0) |> trunc(),
            status_code: Map.get(http_statuses, ts, 0) |> trunc(),
            checked_at: DateTime.from_unix!(trunc(ts))
          }
        end)
        |> Enum.sort_by(& &1.checked_at, {:desc, DateTime})
        |> Enum.take(limit)

      {:ok, checks}
    end
  end

  @doc """
  Gets the latest check status for a monitor.

  Returns `{:ok, %{status, response_time, checked_at}}` or `{:ok, nil}`.
  """
  def get_latest_check(monitor_id) do
    case get_recent_checks(monitor_id, 1) do
      {:ok, [check | _]} -> {:ok, check}
      {:ok, []} -> {:ok, nil}
      {:error, _} -> {:ok, nil}
    end
  end

  # --- Notification Diagnostics ---

  @doc """
  Queries notification delivery counts grouped by channel_type and status over last N days.
  Returns `%{"email" => %{"delivered" => 312, "failed" => 1, ...}, ...}`.
  """
  def get_notification_stats(days \\ 7) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)

    query = "sum by (channel_type, status) (uptrack_notification_delivery)"

    case query_range(query, start_time, now, "#{days}d") do
      {:ok, results} ->
        stats =
          results
          |> Enum.reduce(%{}, fn %{"metric" => m, "values" => vals}, acc ->
            channel_type = m["channel_type"]
            status = m["status"]
            count = vals |> List.last([0, "0"]) |> Enum.at(1) |> parse_float() |> trunc()

            acc
            |> Map.put_new(channel_type, %{})
            |> update_in([channel_type], &Map.put(&1, status, count))
          end)

        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Queries p95 notification delivery duration per channel_type over last N days.
  Returns `%{"email" => 1200.0, "slack" => 350.0, ...}`.
  """
  def get_notification_latency(days \\ 7) do
    now = DateTime.utc_now()
    range = "#{days * 24}h"

    channel_types = ~w(email slack discord telegram)

    results =
      for ct <- channel_types do
        query = "quantile_over_time(0.95, uptrack_notification_duration_ms{channel_type=\"#{ct}\"}[#{range}])"

        case query_instant(query, now) do
          {:ok, value} -> {ct, Float.round(value, 1)}
          {:error, _} -> {ct, 0.0}
        end
      end

    {:ok, Map.new(results)}
  end

  @doc """
  Queries daily notification delivery counts per channel_type and status over last N days.
  Returns list of `%{date: Date, channel_type: String, status: String, count: integer}`.
  """
  def get_notification_daily_trend(days \\ 7) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)

    query = "sum by (channel_type, status) (uptrack_notification_delivery)"

    case query_range(query, start_time, now, "1d") do
      {:ok, results} ->
        points =
          results
          |> Enum.flat_map(fn %{"metric" => m, "values" => vals} ->
            Enum.map(vals, fn [ts, val] ->
              %{
                date: ts |> trunc() |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601(),
                channel_type: m["channel_type"],
                status: m["status"],
                count: parse_float(val) |> trunc()
              }
            end)
          end)

        {:ok, points}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Queries notification delivery counts grouped by org_id and status over last N days.
  Returns list of `%{org_id: String, delivered: integer, failed: integer}`.
  """
  def get_notification_per_org_stats(days \\ 7) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -days * 86400, :second)

    query = "sum by (org_id, status) (uptrack_notification_delivery)"

    case query_range(query, start_time, now, "#{days}d") do
      {:ok, results} ->
        by_org =
          results
          |> Enum.reduce(%{}, fn %{"metric" => m, "values" => vals}, acc ->
            org_id = m["org_id"]
            status = m["status"]
            count = vals |> List.last([0, "0"]) |> Enum.at(1) |> parse_float() |> trunc()

            acc
            |> Map.put_new(org_id, %{"delivered" => 0, "failed" => 0, "skipped" => 0})
            |> update_in([org_id, status], fn _ -> count end)
          end)

        org_list =
          Enum.map(by_org, fn {org_id, counts} ->
            %{org_id: org_id, delivered: counts["delivered"] || 0, failed: counts["failed"] || 0}
          end)

        {:ok, org_list}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_time_values(results) do
    results
    |> List.first(%{})
    |> Map.get("values", [])
    |> Map.new(fn [ts, val] -> {ts, parse_float(val)} end)
  end

  # Extracts a map of %{Date.t() => float} from a query_range result with step=1d.
  defp extract_daily_values(results) do
    results
    |> List.first(%{})
    |> Map.get("values", [])
    |> Map.new(fn [ts, val] ->
      date = ts |> trunc() |> DateTime.from_unix!() |> DateTime.to_date()
      {date, parse_float(val)}
    end)
  end

  defp query_instant(query, time) do
    case vmselect_url() do
      nil ->
        {:ok, 0.0}

      url ->
        query_url = "#{url}/api/v1/query"
        params = %{query: query, time: DateTime.to_unix(time)}

        case Req.get(query_url, params: params) do
          {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => [%{"value" => [_ts, val]} | _]}}}} ->
            {:ok, parse_float(val)}

          {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => []}}}} ->
            {:ok, 0.0}

          _ ->
            {:error, :query_failed}
        end
    end
  rescue
    e ->
      Logger.warning("VictoriaMetrics instant query exception: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp range_duration(start_time, end_time) do
    diff_seconds = DateTime.diff(end_time, start_time, :second)
    "#{diff_seconds}s"
  end


  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_number(val), do: val / 1
  defp parse_float(_), do: 0.0

  defp vmselect_url do
    Application.get_env(:uptrack, :victoriametrics_vmselect_url)
  end
end
