defmodule UptrackWeb.StatusLive do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    try do
      status_page = Monitoring.get_status_page_with_status!(slug)

      # Calculate overall status
      overall_status = calculate_overall_status(status_page.monitors)

      # Get recent incidents for this status page's monitors
      monitor_ids = Enum.map(status_page.monitors, & &1.id)

      recent_incidents =
        if Enum.any?(monitor_ids) do
          # Use user_id 1 for now
          Monitoring.list_recent_incidents(1, 10)
          |> Enum.filter(&(&1.monitor_id in monitor_ids))
        else
          []
        end

      socket =
        socket
        |> assign(:status_page, status_page)
        |> assign(:overall_status, overall_status)
        |> assign(:recent_incidents, recent_incidents)
        |> assign(:page_title, status_page.name)

      {:ok, socket}
    rescue
      Ecto.NoResultsError ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto px-4 py-8 max-w-4xl">
        <!-- Header -->
        <div class="text-center mb-8">
          <%= if @status_page.logo_url do %>
            <img src={@status_page.logo_url} alt={@status_page.name} class="h-16 mx-auto mb-4" />
          <% end %>
          <h1 class="text-4xl font-bold mb-2">{@status_page.name}</h1>
          <%= if @status_page.description do %>
            <p class="text-lg text-base-content/70">{@status_page.description}</p>
          <% end %>
        </div>
        
    <!-- Overall Status -->
        <div class="card bg-base-100 shadow-lg mb-8">
          <div class="card-body text-center">
            <div class="flex items-center justify-center gap-3 mb-2">
              <div class={["w-4 h-4 rounded-full", status_color(@overall_status)]}></div>
              <h2 class="text-2xl font-semibold">
                {status_text(@overall_status)}
              </h2>
            </div>
            <p class="text-base-content/70">
              {status_description(@overall_status, length(@status_page.monitors))}
            </p>
          </div>
        </div>
        
    <!-- Services -->
        <%= if Enum.any?(@status_page.monitors) do %>
          <div class="card bg-base-100 shadow-lg mb-8">
            <div class="card-body">
              <h3 class="card-title text-xl mb-4">Services</h3>
              <div class="space-y-3">
                <%= for monitor <- @status_page.monitors do %>
                  <div class="flex items-center justify-between p-4 rounded-lg bg-base-200">
                    <div class="flex items-center gap-3">
                      <div class={["w-3 h-3 rounded-full", monitor_status_color(monitor)]}></div>
                      <div>
                        <h4 class="font-medium">
                          {display_name(monitor)}
                        </h4>
                        <p class="text-sm text-base-content/60">
                          {monitor.url}
                        </p>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class={["badge", monitor_status_badge(monitor)]}>
                        {monitor_status_text(monitor)}
                      </div>
                      <%= if latest_check = get_latest_check(monitor) do %>
                        <p class="text-xs text-base-content/50 mt-1">
                          <%= if latest_check.response_time do %>
                            {latest_check.response_time}ms
                          <% end %>
                          · {time_ago(latest_check.checked_at)}
                        </p>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-lg mb-8">
            <div class="card-body text-center">
              <h3 class="text-lg font-medium mb-2">No Services Configured</h3>
              <p class="text-base-content/70">
                This status page doesn't have any services configured yet.
              </p>
            </div>
          </div>
        <% end %>
        
    <!-- Recent Incidents -->
        <%= if Enum.any?(@recent_incidents) do %>
          <div class="card bg-base-100 shadow-lg mb-8">
            <div class="card-body">
              <h3 class="card-title text-xl mb-4">Recent Incidents</h3>
              <div class="space-y-4">
                <%= for incident <- @recent_incidents do %>
                  <div class="border-l-4 border-primary pl-4 py-3">
                    <div class="flex items-center gap-2 mb-2">
                      <div class={["w-3 h-3 rounded-full", incident_status_color(incident.status)]}>
                      </div>
                      <h4 class="font-medium">{incident.monitor.name}</h4>
                      <div class={["badge badge-sm", incident_status_badge(incident.status)]}>
                        {incident_status_text(incident.status)}
                      </div>
                      <span class="text-sm text-base-content/60">
                        {format_date(incident.started_at)}
                      </span>
                    </div>

                    <%= if incident.cause do %>
                      <p class="text-base-content/80 mb-2">{incident.cause}</p>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Footer -->
        <div class="text-center text-sm text-base-content/50">
          <p>Last updated: {DateTime.utc_now() |> format_datetime()}</p>
          <%= if @status_page.theme_config["show_powered_by"] != false do %>
            <p class="mt-2">
              Powered by <a href="/" class="link">Uptrack</a>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp calculate_overall_status(monitors) do
    if Enum.empty?(monitors) do
      :unknown
    else
      down_count =
        Enum.count(monitors, fn monitor ->
          case get_latest_check(monitor) do
            nil -> false
            check -> check.status == "down"
          end
        end)

      cond do
        down_count == 0 -> :operational
        down_count == length(monitors) -> :major_outage
        true -> :partial_outage
      end
    end
  end

  defp status_color(:operational), do: "bg-success"
  defp status_color(:partial_outage), do: "bg-warning"
  defp status_color(:major_outage), do: "bg-error"
  defp status_color(_), do: "bg-base-content/30"

  defp status_text(:operational), do: "All Systems Operational"
  defp status_text(:partial_outage), do: "Partial System Outage"
  defp status_text(:major_outage), do: "Major System Outage"
  defp status_text(_), do: "System Status Unknown"

  defp status_description(:operational, count) do
    "All #{count} services are running normally."
  end

  defp status_description(:partial_outage, count) do
    "Some of our #{count} services are experiencing issues."
  end

  defp status_description(:major_outage, count) do
    "All #{count} services are currently down."
  end

  defp status_description(_, count) do
    "Unable to determine status for #{count} services."
  end

  defp monitor_status_color(monitor) do
    case get_latest_check(monitor) do
      nil ->
        "bg-base-content/30"

      check ->
        case check.status do
          "up" -> "bg-success"
          "down" -> "bg-error"
          _ -> "bg-warning"
        end
    end
  end

  defp monitor_status_badge(monitor) do
    case get_latest_check(monitor) do
      nil ->
        "badge-neutral"

      check ->
        case check.status do
          "up" -> "badge-success"
          "down" -> "badge-error"
          _ -> "badge-warning"
        end
    end
  end

  defp monitor_status_text(monitor) do
    case get_latest_check(monitor) do
      nil ->
        "Unknown"

      check ->
        case check.status do
          "up" -> "Operational"
          "down" -> "Down"
          _ -> "Issues"
        end
    end
  end

  defp get_latest_check(monitor) do
    case monitor.monitor_checks do
      [check | _] -> check
      [] -> nil
    end
  end

  defp display_name(monitor) do
    monitor.name
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp incident_status_color("ongoing"), do: "bg-error"
  defp incident_status_color("resolved"), do: "bg-success"
  defp incident_status_color(_), do: "bg-base-content/30"

  defp incident_status_badge("ongoing"), do: "badge-error"
  defp incident_status_badge("resolved"), do: "badge-success"
  defp incident_status_badge(_), do: "badge-neutral"

  defp incident_status_text("ongoing"), do: "Ongoing"
  defp incident_status_text("resolved"), do: "Resolved"
  defp incident_status_text(_), do: "Unknown"
end
