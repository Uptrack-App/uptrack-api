defmodule Uptrack.MCP.Resources do
  @moduledoc "MCP Resource definitions for Uptrack monitoring data."

  alias Uptrack.Monitoring

  @resources [
    %{
      "uri" => "uptrack://monitors",
      "name" => "Monitors",
      "description" => "All monitors with their current status and uptime percentage.",
      "mimeType" => "application/json"
    },
    %{
      "uri" => "uptrack://incidents",
      "name" => "Recent Incidents",
      "description" => "The 50 most recent incidents across all monitors.",
      "mimeType" => "application/json"
    },
    %{
      "uri" => "uptrack://dashboard",
      "name" => "Dashboard Stats",
      "description" => "Aggregate stats: total monitors, monitors up/down, average uptime, active incidents.",
      "mimeType" => "application/json"
    }
  ]

  def definitions, do: @resources

  def read("uptrack://monitors", org_id) do
    result = Monitoring.list_monitors(org_id)
    monitors = if is_map(result) and Map.has_key?(result, :monitors), do: result.monitors, else: result

    data = Enum.map(monitors, fn m ->
      latest = List.first(m.monitor_checks)
      uptime = Monitoring.get_uptime_percentage(m.id, 30)
      %{
        id: m.id,
        name: m.name,
        url: m.url,
        type: m.monitor_type,
        status: if(latest, do: latest.status, else: "unknown"),
        response_time: latest && latest.response_time,
        interval: m.interval,
        is_active: m.status == "active",
        uptime_percentage: uptime
      }
    end)

    {:ok, Jason.encode!(data)}
  end

  def read("uptrack://incidents", org_id) do
    incidents = Monitoring.list_recent_incidents(org_id, 50)

    data = Enum.map(incidents, fn i ->
      %{
        id: i.id,
        status: i.status,
        cause: i.cause,
        started_at: i.started_at,
        resolved_at: i.resolved_at,
        duration: i.duration,
        monitor_name: i.monitor && i.monitor.name,
        monitor_id: i.monitor && i.monitor.id
      }
    end)

    {:ok, Jason.encode!(data)}
  end

  def read("uptrack://dashboard", org_id) do
    stats = Monitoring.get_dashboard_stats(org_id)
    overall_uptime = Monitoring.get_organization_overall_uptime(org_id, 30)
    data = Map.put(stats, :overall_uptime_30d, overall_uptime)
    {:ok, Jason.encode!(data)}
  end

  def read(uri, _org_id) do
    {:error, "Unknown resource: #{uri}"}
  end
end
