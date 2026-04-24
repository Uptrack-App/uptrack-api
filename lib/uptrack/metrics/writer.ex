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
        status_bucket = status_code_bucket(check.status_code)
        fallback_region = Application.get_env(:uptrack, :node_region, "eu")

        base_labels = %{monitor_id: monitor_id, org_id: org_id}

        monitor_level_lines = [
          metric_line("uptrack_monitor_status", status_value, Map.put(base_labels, :name, monitor.name), timestamp),
          metric_line("uptrack_monitor_response_time_ms", check.response_time || 0, base_labels, timestamp),
          metric_line("uptrack_monitor_http_status", check.status_code || 0, base_labels, timestamp)
        ]

        # Per-region samples. `region_results` is populated by
        # `MonitorProcess.apply_consensus/1` with one entry per region
        # whose result reached us via pg. When it's empty (e.g. during
        # tests or if consensus failed), fall back to one sample
        # labeled with the emitting node's region so the metric is
        # never silently absent.
        region_samples =
          case check.region_results do
            results when is_map(results) and map_size(results) > 0 ->
              Enum.map(results, fn {region, region_result} ->
                %{
                  region: to_string(region),
                  status: Map.get(region_result, :status) || Map.get(region_result, "status") || check.status,
                  response_time:
                    Map.get(region_result, :response_time) ||
                      Map.get(region_result, "response_time") ||
                      check.response_time ||
                      0
                }
              end)

            _ ->
              [%{region: fallback_region, status: check.status, response_time: check.response_time || 0}]
          end

        region_lines =
          for sample <- region_samples do
            metric_line(
              "uptrack_check_duration_ms",
              sample.response_time,
              Map.merge(base_labels, %{status: sample.status, region: sample.region}),
              timestamp
            )
          end

        lines = monitor_level_lines ++ region_lines

        lines =
          if check.status == "down" do
            failure_samples =
              for sample <- region_samples, sample.status == "down" do
                metric_line(
                  "uptrack_check_failure_events",
                  1,
                  Map.merge(base_labels, %{status_code: status_bucket, region: sample.region}),
                  timestamp
                )
              end

            # If no per-region sample marked down (edge case on first
            # consensus tick), emit one with the fallback region so the
            # counter is never missed.
            failure_samples =
              if failure_samples == [] do
                [
                  metric_line(
                    "uptrack_check_failure_events",
                    1,
                    Map.merge(base_labels, %{status_code: status_bucket, region: fallback_region}),
                    timestamp
                  )
                ]
              else
                failure_samples
              end

            failure_samples ++ lines
          else
            lines
          end

        body = Enum.join(lines, "\n")
        # Write to all VM instances for HA (fire-and-forget to secondaries)
        Enum.each(urls, &do_write(&1, body))
    end
  end

  # Bucket raw HTTP status codes into low-cardinality labels so VM
  # series count stays bounded. Raw codes (418, 451, 522, ...) would
  # inflate cardinality without adding dashboard value.
  defp status_code_bucket(nil), do: "none"
  defp status_code_bucket(code) when is_integer(code) and code in 200..299, do: "2xx"
  defp status_code_bucket(code) when is_integer(code) and code in 300..399, do: "3xx"
  defp status_code_bucket(code) when is_integer(code) and code in 400..499, do: "4xx"
  defp status_code_bucket(code) when is_integer(code) and code in 500..599, do: "5xx"
  defp status_code_bucket(_), do: "other"

  @doc """
  Emits a counter sample for the number of forensic events the Batcher
  has dropped due to buffer overflow. Called from
  `Uptrack.Failures.Batcher.Shard` on every drop-oldest event.
  """
  def write_forensic_drop(count) when is_integer(count) and count > 0 do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
        timestamp = System.os_time(:millisecond)
        region = Application.get_env(:uptrack, :node_region, "eu")

        body =
          metric_line(
            "uptrack_forensic_events_dropped_total",
            count,
            %{region: region},
            timestamp
          )

        Enum.each(urls, &do_write(&1, body))
    end
  end

  def write_forensic_drop(_), do: :ok

  @doc """
  Emits a consensus-strategy observation: one sample per monitor per
  decide cycle. Labels carry the strategy module and the returned
  state so we can alert on `:insufficient_data` rate or watch the
  mix of verdicts per strategy. Change #11 §8.
  """
  def write_consensus_observation(monitor_id, strategy, state)
      when is_binary(monitor_id) and is_atom(strategy) and is_atom(state) do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
        timestamp = System.os_time(:millisecond)
        region = Application.get_env(:uptrack, :node_region, "eu")
        strategy_name = strategy |> Module.split() |> List.last() |> to_string()

        body =
          metric_line(
            "uptrack_consensus_strategy",
            1,
            %{
              monitor_id: monitor_id,
              strategy: strategy_name,
              state: Atom.to_string(state),
              region: region
            },
            timestamp
          )

        Enum.each(urls, &do_write(&1, body))
    end
  end

  @doc """
  Emits the current flap percent for a monitor. Change #11 §8.
  """
  def write_flap_percent(monitor_id, percent) when is_binary(monitor_id) and is_float(percent) do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
        timestamp = System.os_time(:millisecond)

        body =
          metric_line(
            "uptrack_monitor_flap_percent",
            percent,
            %{monitor_id: monitor_id},
            timestamp
          )

        Enum.each(urls, &do_write(&1, body))
    end
  end

  @doc "Counts alerts dispatched at a given level. Change #11 §8."
  def write_alert_level(level) when is_binary(level) do
    case vminsert_urls() do
      [] ->
        :ok

      urls ->
        timestamp = System.os_time(:millisecond)

        body =
          metric_line(
            "uptrack_alert_level_events",
            1,
            %{level: level},
            timestamp
          )

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
