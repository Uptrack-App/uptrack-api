defmodule Uptrack.Monitoring.CheckExecutor do
  @moduledoc """
  Executes a monitoring check and returns a result map.

  Impure (makes HTTP/TCP/DNS requests) but has no DB writes or alerts.
  Called by MonitorProcess (GenServer) to separate check execution
  from result recording and alerting.

  Returns:
    {:ok, %{status: "up"|"down", response_time: integer, status_code: integer|nil,
            error_message: nil|string, response_headers: map, response_body: string}}
  """

  alias Uptrack.Monitoring.Monitor

  @doc """
  Executes a check and returns a result map ready for DB insertion.

  Delegates to CheckWorker.perform_check/1 which has all the check logic
  (HTTP, TCP, DNS, SSL, ping, keyword). This avoids duplicating 500+ lines
  of check code. The only difference is MonitorProcess controls what happens
  AFTER the check (alerts, consecutive counting) differently than Oban.
  """
  def execute(%Monitor{} = monitor) do
    start_time = System.monotonic_time(:millisecond)

    result = Uptrack.Monitoring.CheckWorker.execute_raw_check(monitor)

    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    build_check_attrs(monitor, result, response_time)
  end

  defp build_check_attrs(monitor, {:ok, status_code, headers, body}, response_time) do
    expected = Map.get(monitor.settings, "expected_status_code")
    assertions = Map.get(monitor.settings, "assertions", [])

    base = %{
      monitor_id: monitor.id,
      response_time: response_time,
      status_code: status_code,
      checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      response_headers: headers,
      response_body: truncate_body(body)
    }

    cond do
      expected && status_code != expected ->
        Map.merge(base, %{status: "down", error_message: "Expected status #{expected}, got #{status_code}"})

      assertions != [] ->
        case Uptrack.Monitoring.Assertions.evaluate(assertions, status_code, headers, body) do
          :ok -> Map.put(base, :status, "up")
          {:error, msg} -> Map.merge(base, %{status: "down", error_message: "Assertion failed: #{msg}"})
        end

      true ->
        Map.put(base, :status, "up")
    end
  end

  defp build_check_attrs(monitor, {:error, reason}, response_time) do
    %{
      monitor_id: monitor.id,
      status: "down",
      response_time: response_time,
      checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      error_message: to_string(reason)
    }
  end

  defp truncate_body(body, max \\ 1_000)
  defp truncate_body(nil, _max), do: nil
  defp truncate_body(body, max) when is_binary(body) do
    if String.length(body) > max do
      String.slice(body, 0, max) <> "... [truncated]"
    else
      body
    end
  end
  defp truncate_body(_, _max), do: nil
end
