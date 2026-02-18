defmodule UptrackWeb.Api.StatusPageJSON do
  alias Uptrack.Monitoring.{StatusPage, Incident, MonitorCheck}

  def index(%{status_pages: pages}) do
    %{data: for(p <- pages, do: page_data(p))}
  end

  def show(%{status_page: page}) do
    %{data: page_data(page)}
  end

  def show_public(%{
        status_page: page,
        overall_status: overall_status,
        uptime: uptime,
        recent_incidents: incidents,
        maintenance_windows: maintenance_windows
      }) do
    monitors_data =
      Enum.map(page.monitors, fn monitor ->
        latest_check = List.first(monitor.monitor_checks)

        %{
          name: monitor.name,
          status: check_status(latest_check),
          response_time: latest_check && latest_check.response_time,
          last_checked_at: latest_check && latest_check.checked_at
        }
      end)

    %{
      data: %{
        name: page.name,
        slug: page.slug,
        description: page.description,
        logo_url: page.logo_url,
        allow_subscriptions: page.allow_subscriptions,
        overall_status: overall_status,
        uptime_percentage: uptime,
        monitors: monitors_data,
        recent_incidents: for(i <- incidents, do: public_incident_data(i)),
        maintenance_windows: for(mw <- maintenance_windows, do: maintenance_data(mw))
      }
    }
  end

  defp page_data(%StatusPage{} = p) do
    base = %{
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      is_public: p.is_public,
      custom_domain: p.custom_domain,
      logo_url: p.logo_url,
      allow_subscriptions: p.allow_subscriptions,
      default_language: p.default_language,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }

    if Ecto.assoc_loaded?(p.status_page_monitors) do
      Map.put(base, :status_page_monitors, Enum.map(p.status_page_monitors, &monitor_assignment/1))
    else
      base
    end
  end

  defp monitor_assignment(spm) do
    %{
      id: spm.id,
      monitor_id: spm.monitor_id,
      monitor_name: spm.monitor.name,
      display_name: spm.display_name,
      sort_order: spm.sort_order
    }
  end

  defp check_status(%MonitorCheck{status: status}), do: status
  defp check_status(_), do: "unknown"

  defp maintenance_data(mw) do
    %{
      title: mw.title,
      status: mw.status,
      start_time: mw.start_time,
      end_time: mw.end_time
    }
  end

  defp public_incident_data(%Incident{} = i) do
    monitor_name =
      case i do
        %{monitor: %{name: name}} -> name
        _ -> nil
      end

    %{
      id: i.id,
      monitor_name: monitor_name,
      status: i.status,
      cause: i.cause,
      started_at: i.started_at,
      resolved_at: i.resolved_at,
      duration: i.duration
    }
  end
end
