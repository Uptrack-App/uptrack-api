defmodule UptrackWeb.DashboardLive do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Get user from session/auth
    # Placeholder - will be replaced with actual auth
    user_id = 1

    stats = Monitoring.get_dashboard_stats(user_id)
    monitors = Monitoring.get_dashboard_monitors(user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(user_id)

    # Subscribe to real-time updates for this user
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Uptrack.PubSub, "user:#{user_id}")
    end

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:stats, stats)
      |> assign(:monitors, monitors)
      |> assign(:overall_uptime, overall_uptime)
      |> assign(:page_title, "Dashboard")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dashboard")
  end

  defp apply_action(socket, :new_monitor, _params) do
    socket
    |> assign(:page_title, "New Monitor")
    |> assign(:monitor, %Uptrack.Monitoring.Monitor{})
  end

  @impl true
  def handle_event("delete_monitor", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(id)
    {:ok, _} = Monitoring.delete_monitor(monitor)

    # Refresh the data
    stats = Monitoring.get_dashboard_stats(socket.assigns.user_id)
    monitors = Monitoring.get_dashboard_monitors(socket.assigns.user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(socket.assigns.user_id)

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:monitors, monitors)
      |> assign(:overall_uptime, overall_uptime)
      |> put_flash(:info, "Monitor deleted successfully")

    {:noreply, socket}
  end

  def handle_event("check_now", %{"id" => id}, socket) do
    monitor_id = String.to_integer(id)

    case Uptrack.Monitoring.Scheduler.check_monitor(monitor_id) do
      {:ok, :scheduled} ->
        socket = put_flash(socket, :info, "Check scheduled successfully")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to schedule check: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({UptrackWeb.MonitorLive.FormComponent, {:saved, _monitor}}, socket) do
    # Refresh the data when a monitor is saved
    stats = Monitoring.get_dashboard_stats(socket.assigns.user_id)
    monitors = Monitoring.get_dashboard_monitors(socket.assigns.user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(socket.assigns.user_id)

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:monitors, monitors)
      |> assign(:overall_uptime, overall_uptime)

    {:noreply, socket}
  end

  def handle_info({:check_completed, event_data}, socket) do
    # Update the specific monitor in the list
    monitors = update_monitor_in_list(socket.assigns.monitors, event_data)

    # Refresh stats
    stats = Monitoring.get_dashboard_stats(socket.assigns.user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(socket.assigns.user_id)

    socket =
      socket
      |> assign(:monitors, monitors)
      |> assign(:stats, stats)
      |> assign(:overall_uptime, overall_uptime)
      |> put_flash(:info, "Monitor #{event_data["monitor_name"]} is #{event_data["status"]}")

    {:noreply, socket}
  end

  def handle_info({:incident_created, event_data}, socket) do
    # Refresh data to show new incident
    stats = Monitoring.get_dashboard_stats(socket.assigns.user_id)
    monitors = Monitoring.get_dashboard_monitors(socket.assigns.user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(socket.assigns.user_id)

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:monitors, monitors)
      |> assign(:overall_uptime, overall_uptime)
      |> put_flash(:error, "🚨 Incident: #{event_data["monitor_name"]} is down!")

    {:noreply, socket}
  end

  def handle_info({:incident_resolved, event_data}, socket) do
    # Refresh data to clear incident
    stats = Monitoring.get_dashboard_stats(socket.assigns.user_id)
    monitors = Monitoring.get_dashboard_monitors(socket.assigns.user_id)
    overall_uptime = Monitoring.get_user_overall_uptime(socket.assigns.user_id)

    duration_text = format_duration(event_data["duration"])

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:monitors, monitors)
      |> assign(:overall_uptime, overall_uptime)
      |> put_flash(
        :info,
        "✅ Resolved: #{event_data["monitor_name"]} is back up! (Downtime: #{duration_text})"
      )

    {:noreply, socket}
  end

  def handle_info({_event, _data}, socket) do
    {:noreply, socket}
  end

  defp status_color("up"), do: "text-success"
  defp status_color("down"), do: "text-error"
  defp status_color(_), do: "text-warning"

  defp status_badge("up"), do: "badge-success"
  defp status_badge("down"), do: "badge-error"
  defp status_badge(_), do: "badge-warning"

  defp format_uptime(uptime) when is_float(uptime) do
    "#{:erlang.float_to_binary(uptime, decimals: 1)}%"
  end

  defp format_uptime(_), do: "—"

  defp format_response_time(nil), do: "—"

  defp format_response_time(time) when is_integer(time) do
    cond do
      time < 1000 -> "#{time}ms"
      time < 60000 -> "#{Float.round(time / 1000, 1)}s"
      true -> "#{Float.round(time / 60000, 1)}m"
    end
  end

  defp latest_check(monitor) do
    case monitor.monitor_checks do
      [check | _] -> check
      [] -> nil
    end
  end

  defp update_monitor_in_list(monitors, event_data) do
    monitor_id = event_data["monitor_id"]

    Enum.map(monitors, fn monitor ->
      if monitor.id == monitor_id do
        # Create a fake check record for immediate UI update
        fake_check = %{
          status: event_data["status"],
          response_time: event_data["response_time"],
          checked_at: event_data["checked_at"],
          error_message: event_data["error_message"]
        }

        %{monitor | monitor_checks: [fake_check]}
      else
        monitor
      end
    end)
  end

  defp format_duration(nil), do: "Unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end
