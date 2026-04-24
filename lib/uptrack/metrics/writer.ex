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
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
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
        # Write to all VM instances for HA (fire-and-forget to secondaries)
        Enum.each(urls, &do_write(&1, body))
    end
  end

  @doc """
  Writes an incident event metric.
  """
  def write_incident_event(monitor, event_type) do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
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

        Enum.each(urls, &do_write(&1, body))
    end
  end

  @doc """
  Writes notification delivery metrics to VictoriaMetrics.

  Publishes:
  - `uptrack_notification_delivery` (counter, 1 per delivery) with channel_type, status, org_id labels
  - `uptrack_notification_duration_ms` (latency) with channel_type label
  """
  def write_notification_delivery(channel_type, status, duration_ms, org_id) do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
        timestamp = System.os_time(:millisecond)

        lines = [
          metric_line("uptrack_notification_delivery", 1,
            %{channel_type: channel_type, status: status, org_id: to_string(org_id)}, timestamp),
          metric_line("uptrack_notification_duration_ms", duration_ms,
            %{channel_type: channel_type}, timestamp)
        ]

        body = Enum.join(lines, "\n")
        Enum.each(urls, &do_write(&1, body))
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

  defp vminsert_urls do
    case Application.get_env(:uptrack, :victoriametrics_vminsert_url) do
      nil -> []
      url when is_binary(url) -> String.split(url, ",", trim: true) |> Enum.map(&String.trim/1)
      _ -> []
    end
  end
end
