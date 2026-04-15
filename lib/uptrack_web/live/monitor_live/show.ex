defmodule UptrackWeb.MonitorLive.Show do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    %{current_organization: org} = socket.assigns
    monitor = Monitoring.get_organization_monitor!(org.id, id)
    recent_checks = case Uptrack.Metrics.Reader.get_recent_checks(id, 100) do
      {:ok, checks} -> checks
      {:error, _} -> []
    end
    uptime = Monitoring.get_uptime_percentage(id)

    incidents =
      Monitoring.list_recent_incidents(org.id, 10)
      |> Enum.filter(&(&1.monitor_id == monitor.id))

    # Get analytics data
    uptime_chart_data = Monitoring.get_uptime_chart_data(monitor.id, 30)
    response_time_trends = Monitoring.get_response_time_trends(monitor.id, 30)
    incident_stats = Monitoring.get_incident_stats(monitor.id, 30)

    socket =
      socket
      |> assign(:page_title, monitor.name)
      |> assign(:monitor, monitor)
      |> assign(:recent_checks, recent_checks)
      |> assign(:uptime, uptime)
      |> assign(:incidents, incidents)
      |> assign(:uptime_chart_data, uptime_chart_data)
      |> assign(:response_time_trends, response_time_trends)
      |> assign(:incident_stats, incident_stats)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(id)
    {:ok, _} = Monitoring.delete_monitor(monitor)

    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  defp status_color("up"), do: "text-success"
  defp status_color("down"), do: "text-error"
  defp status_color(_), do: "text-warning"

  defp status_badge("up"), do: "badge-success"
  defp status_badge("down"), do: "badge-error"
  defp status_badge(_), do: "badge-warning"

  defp format_response_time(nil), do: "—"

  defp format_response_time(time) when is_integer(time) do
    cond do
      time < 1000 -> "#{time}ms"
      time < 60000 -> "#{Float.round(time / 1000, 1)}s"
      true -> "#{Float.round(time / 60000, 1)}m"
    end
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end
