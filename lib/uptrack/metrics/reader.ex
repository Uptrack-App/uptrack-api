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
