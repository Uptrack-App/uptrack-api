defmodule Uptrack.Metrics.Writer do
  @moduledoc """
  Writes uptime check metrics to VictoriaMetrics via Prometheus import API.

  Metrics are written in Prometheus exposition format to the vminsert endpoint.
  If VictoriaMetrics is not configured, writes are silently skipped.
  """

  require Logger

  @doc """
  Writes check result metrics for a monitor to VictoriaMetrics.

  Publishes:
  - `uptrack_monitor_status` (1=up, 0=down)
  - `uptrack_monitor_response_time_ms`
  - `uptrack_monitor_http_status`
  """
  def write_check_result(monitor, check) do
    case vminsert_url() do
      nil ->
        :ok

      url ->
        timestamp = System.os_time(:millisecond)
        monitor_id = to_string(monitor.id)
        org_id = to_string(monitor.organization_id)

        status_value = if check.status == "up", do: 1, else: 0

        lines = [
          metric_line("uptrack_monitor_status", status_value, %{monitor_id: monitor_id, org_id: org_id, name: monitor.name}, timestamp),
          metric_line("uptrack_monitor_response_time_ms", check.response_time || 0, %{monitor_id: monitor_id, org_id: org_id}, timestamp),
          metric_line("uptrack_monitor_http_status", check.status_code || 0, %{monitor_id: monitor_id, org_id: org_id}, timestamp)
        ]

        body = Enum.join(lines, "\n")
        do_write(url, body)
    end
  end

  @doc """
  Writes an incident event metric.
  """
  def write_incident_event(monitor, event_type) do
    case vminsert_url() do
      nil ->
        :ok

      url ->
        timestamp = System.os_time(:millisecond)
        monitor_id = to_string(monitor.id)
        org_id = to_string(monitor.organization_id)

        body =
          metric_line(
            "uptrack_incident_event",
            1,
            %{monitor_id: monitor_id, org_id: org_id, event: event_type},
            timestamp
          )

        do_write(url, body)
    end
  end

  defp do_write(url, body) do
    import_url = "#{url}/api/v1/import/prometheus"

    case Req.post(import_url, body: body, headers: [{"content-type", "text/plain"}]) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("VictoriaMetrics write failed: HTTP #{status} - #{inspect(resp_body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("VictoriaMetrics write error: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("VictoriaMetrics write exception: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp metric_line(name, value, labels, timestamp) do
    label_str =
      labels
      |> Enum.map(fn {k, v} -> ~s(#{k}="#{escape_label_value(v)}") end)
      |> Enum.join(",")

    "#{name}{#{label_str}} #{value} #{timestamp}"
  end

  defp escape_label_value(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_label_value(value), do: to_string(value)

  defp vminsert_url do
    Application.get_env(:uptrack, :victoriametrics_vminsert_url)
  end
end
