defmodule Uptrack.MCP.Tools do
  @moduledoc "MCP tool definitions and execution for Uptrack monitoring."

  alias Uptrack.MCP.JsonRpc
  alias Uptrack.{Monitoring, Organizations}

  def definitions do
    [
      JsonRpc.define_tool("list_monitors", "List all monitors with current status, URL, and response time.", %{}, []),
      JsonRpc.define_tool("get_monitor", "Get detailed info for a specific monitor including uptime percentage.",
        %{"monitor_id" => JsonRpc.prop("string", "Monitor ID")}, ["monitor_id"]),
      JsonRpc.define_tool("create_monitor", "Create a new monitor.",
        %{
          "url" => JsonRpc.prop("string", "URL or domain to monitor"),
          "name" => JsonRpc.prop("string", "Display name for the monitor"),
          "monitor_type" => JsonRpc.prop("string", "Type: http, dns, ssl, heartbeat"),
          "interval" => JsonRpc.prop("integer", "Check interval in seconds (default 180)")
        }, ["url", "name"]),
      JsonRpc.define_tool("delete_monitor", "Delete a monitor.",
        %{"monitor_id" => JsonRpc.prop("string", "Monitor ID")}, ["monitor_id"]),
      JsonRpc.define_tool("pause_monitor", "Pause a monitor (stop checking).",
        %{"monitor_id" => JsonRpc.prop("string", "Monitor ID")}, ["monitor_id"]),
      JsonRpc.define_tool("resume_monitor", "Resume a paused monitor.",
        %{"monitor_id" => JsonRpc.prop("string", "Monitor ID")}, ["monitor_id"]),
      JsonRpc.define_tool("list_incidents", "List recent incidents with cause, status, and duration.",
        %{"limit" => JsonRpc.prop("integer", "Number of incidents to return (default 10)")}, []),
      JsonRpc.define_tool("get_dashboard_stats", "Get dashboard overview: uptime %, active monitors, ongoing incidents.", %{}, []),
      JsonRpc.define_tool("get_monitor_analytics", "Get response time trends and uptime chart for a monitor.",
        %{
          "monitor_id" => JsonRpc.prop("string", "Monitor ID"),
          "days" => JsonRpc.prop("integer", "Number of days (default 30)")
        }, ["monitor_id"]),
      JsonRpc.define_tool("list_status_pages", "List all status pages with their public URLs.", %{}, []),
      JsonRpc.define_tool("list_alert_channels", "List configured alert channels.", %{}, []),
    ]
  end

  def call("list_monitors", _args, org_id) do
    monitors = Monitoring.list_monitors(org_id)

    {:ok, Enum.map(monitors, fn m ->
      latest = List.first(m.monitor_checks)
      %{
        id: m.id,
        name: m.name,
        url: m.url,
        type: m.monitor_type,
        status: if(latest, do: latest.status, else: "unknown"),
        response_time: latest && latest.response_time,
        interval: m.interval,
        is_active: m.is_active
      }
    end)}
  end

  def call("get_monitor", %{"monitor_id" => id}, org_id) do
    case Monitoring.get_organization_monitor(org_id, id) do
      nil -> {:error, "Monitor not found"}
      monitor ->
        uptime = Monitoring.get_uptime_percentage(id, 30)
        latest = List.first(monitor.monitor_checks)
        {:ok, %{
          id: monitor.id, name: monitor.name, url: monitor.url,
          type: monitor.monitor_type, interval: monitor.interval,
          is_active: monitor.is_active,
          status: if(latest, do: latest.status, else: "unknown"),
          response_time: latest && latest.response_time,
          uptime_30d: uptime
        }}
    end
  end

  def call("create_monitor", args, org_id) do
    org = Organizations.get_organization!(org_id)
    # Get first user in org as owner
    [user | _] = Uptrack.Teams.list_members(org_id)

    attrs = %{
      "url" => args["url"],
      "name" => args["name"],
      "monitor_type" => args["monitor_type"] || "http",
      "interval" => args["interval"] || 180,
      "organization_id" => org_id,
      "user_id" => user.id
    }

    case Uptrack.Billing.check_plan_limit(org, :monitors) do
      :ok ->
        case Monitoring.create_monitor(attrs) do
          {:ok, monitor} -> {:ok, %{id: monitor.id, name: monitor.name, url: monitor.url, type: monitor.monitor_type}}
          {:error, changeset} -> {:error, "Failed to create monitor: #{inspect(changeset.errors)}"}
        end
      {:error, msg} -> {:error, msg}
    end
  end

  def call("delete_monitor", %{"monitor_id" => id}, org_id) do
    case Monitoring.get_organization_monitor(org_id, id) do
      nil -> {:error, "Monitor not found"}
      monitor ->
        case Monitoring.delete_monitor(monitor) do
          {:ok, _} -> {:ok, %{deleted: true, id: id}}
          {:error, _} -> {:error, "Failed to delete monitor"}
        end
    end
  end

  def call("pause_monitor", %{"monitor_id" => id}, org_id) do
    case Monitoring.get_organization_monitor(org_id, id) do
      nil -> {:error, "Monitor not found"}
      monitor ->
        case Monitoring.update_monitor(monitor, %{is_active: false}) do
          {:ok, m} -> {:ok, %{id: m.id, name: m.name, is_active: false}}
          {:error, _} -> {:error, "Failed to pause monitor"}
        end
    end
  end

  def call("resume_monitor", %{"monitor_id" => id}, org_id) do
    case Monitoring.get_organization_monitor(org_id, id) do
      nil -> {:error, "Monitor not found"}
      monitor ->
        case Monitoring.update_monitor(monitor, %{is_active: true}) do
          {:ok, m} -> {:ok, %{id: m.id, name: m.name, is_active: true}}
          {:error, _} -> {:error, "Failed to resume monitor"}
        end
    end
  end

  def call("list_incidents", args, org_id) do
    limit = args["limit"] || 10
    incidents = Monitoring.list_recent_incidents(org_id, limit)

    {:ok, Enum.map(incidents, fn i ->
      %{
        id: i.id, status: i.status, cause: i.cause,
        started_at: i.started_at, resolved_at: i.resolved_at,
        duration: i.duration,
        monitor_name: i.monitor && i.monitor.name
      }
    end)}
  end

  def call("get_dashboard_stats", _args, org_id) do
    stats = Monitoring.get_dashboard_stats(org_id)
    overall_uptime = Monitoring.get_organization_overall_uptime(org_id, 30)
    {:ok, Map.put(stats, :overall_uptime_30d, overall_uptime)}
  end

  def call("get_monitor_analytics", %{"monitor_id" => id} = args, org_id) do
    case Monitoring.get_organization_monitor(org_id, id) do
      nil -> {:error, "Monitor not found"}
      _monitor ->
        days = args["days"] || 30
        uptime_chart = Monitoring.get_uptime_chart_data(id, days)
        response_times = Monitoring.get_response_time_trends(id, days)
        incident_stats = Monitoring.get_incident_stats(id, days)
        {:ok, %{monitor_id: id, days: days, uptime_chart: uptime_chart, response_times: response_times, incident_stats: incident_stats}}
    end
  end

  def call("list_status_pages", _args, org_id) do
    pages = Monitoring.list_status_pages(org_id)
    {:ok, Enum.map(pages, fn p ->
      %{id: p.id, name: p.name, slug: p.slug, is_public: p.is_public, url: "https://uptrack.app/status/#{p.slug}"}
    end)}
  end

  def call("list_alert_channels", _args, org_id) do
    channels = Monitoring.list_alert_channels(org_id)
    {:ok, Enum.map(channels, fn c ->
      %{id: c.id, name: c.name, type: c.type, is_active: c.is_active}
    end)}
  end

  def call(tool_name, _args, _org_id) do
    {:error, "Unknown tool: #{tool_name}"}
  end
end
