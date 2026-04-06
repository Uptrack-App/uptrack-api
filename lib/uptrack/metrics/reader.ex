defmodule Uptrack.Metrics.Reader do
  @moduledoc """
  Reads uptime metrics from VictoriaMetrics via the vmselect query API.

  Used to display historical uptime data, response time charts, etc.
  """

  require Logger

  @doc """
  Queries uptime percentage for a monitor over a time range.

  Returns a float between 0.0 and 100.0.
  """
  def get_uptime_percentage(monitor_id, start_time, end_time) do
    query = "avg_over_time(uptrack_monitor_status{monitor_id=\"#{monitor_id}\"}[1h])"

    case query_range(query, start_time, end_time, "1h") do
      {:ok, results} ->
        values = extract_values(results)

        if Enum.empty?(values) do
          {:ok, 100.0}
        else
          avg = Enum.sum(values) / length(values) * 100
          {:ok, Float.round(avg, 2)}
        end

      {:error, reason} ->
        {:error, reason}
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

  defp extract_time_values(results) do
    results
    |> List.first(%{})
    |> Map.get("values", [])
    |> Map.new(fn [ts, val] -> {ts, parse_float(val)} end)
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

  defp extract_values(results) do
    results
    |> Enum.flat_map(fn result ->
      result
      |> Map.get("values", [])
      |> Enum.map(fn [_ts, val] -> parse_float(val) end)
    end)
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
