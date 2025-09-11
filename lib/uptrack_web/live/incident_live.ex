defmodule UptrackWeb.IncidentLive do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Incident, IncidentUpdate}

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Get user from session/auth
    # Placeholder - will be replaced with actual auth
    user_id = 1

    incidents = Monitoring.list_incidents(user_id)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:incidents, incidents)
      |> assign(:page_title, "Incidents")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Incidents")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    incident = Monitoring.get_incident_with_updates!(id)

    socket
    |> assign(:page_title, "Incident Details")
    |> assign(:incident, incident)
    |> assign(:incident_update, %IncidentUpdate{})
  end

  @impl true
  def handle_event("resolve_incident", %{"id" => id}, socket) do
    incident = Monitoring.get_incident!(id)

    case Monitoring.manually_resolve_incident(incident) do
      {:ok, _incident} ->
        # Refresh incidents list
        incidents = Monitoring.list_incidents(socket.assigns.user_id)

        socket =
          socket
          |> assign(:incidents, incidents)
          |> put_flash(:info, "Incident resolved successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to resolve incident")
        {:noreply, socket}
    end
  end

  def handle_event("add_update", %{"incident_update" => update_params}, socket) do
    update_params =
      update_params
      |> Map.put("incident_id", socket.assigns.incident.id)
      |> Map.put("user_id", socket.assigns.user_id)

    case Monitoring.create_incident_update(update_params) do
      {:ok, _update} ->
        # Refresh incident with updates
        incident = Monitoring.get_incident_with_updates!(socket.assigns.incident.id)

        socket =
          socket
          |> assign(:incident, incident)
          |> assign(:incident_update, %IncidentUpdate{})
          |> put_flash(:info, "Update added successfully")

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> assign(:incident_update, changeset)
          |> put_flash(:error, "Failed to add update")

        {:noreply, socket}
    end
  end

  def handle_event("validate_update", %{"incident_update" => update_params}, socket) do
    changeset =
      %IncidentUpdate{}
      |> Monitoring.change_incident_update(update_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :incident_update, changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold">
            {if @live_action == :show, do: "Incident Details", else: "Incidents"}
          </h1>
          <p class="text-base-content/70">
            {if @live_action == :show,
              do: "Manage incident updates and resolution",
              else: "View and manage service incidents"}
          </p>
        </div>
        <%= if @live_action == :show do %>
          <.link navigate={~p"/dashboard/incidents"} class="btn btn-ghost">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Incidents
          </.link>
        <% end %>
      </div>
      
    <!-- Navigation Tabs -->
      <div class="tabs tabs-bordered">
        <.link navigate={~p"/dashboard"} class="tab">
          <.icon name="hero-chart-bar" class="w-4 h-4" /> Dashboard
        </.link>
        <.link navigate={~p"/dashboard/alerts"} class="tab">
          <.icon name="hero-bell" class="w-4 h-4" /> Alert Channels
        </.link>
        <.link navigate={~p"/dashboard/status-pages"} class="tab">
          <.icon name="hero-globe-alt" class="w-4 h-4" /> Status Pages
        </.link>
        <.link
          navigate={~p"/dashboard/incidents"}
          class={["tab", if(@live_action in [:index, :show], do: "tab-active", else: "")]}
        >
          <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> Incidents
        </.link>
      </div>
      
    <!-- Content based on live_action -->
      <%= if @live_action == :index do %>
        {render_incidents_list(assigns)}
      <% else %>
        {render_incident_details(assigns)}
      <% end %>
    </div>
    """
  end

  defp render_incidents_list(assigns) do
    ~H"""
    <!-- Incidents List -->
    <div class="space-y-4">
      <%= if Enum.empty?(@incidents) do %>
        <div class="card bg-base-100 shadow p-12 text-center">
          <.icon name="hero-check-circle" class="w-16 h-16 mx-auto text-success mb-4" />
          <h3 class="text-lg font-medium mb-2">No incidents recorded</h3>
          <p class="text-base-content/70">Great! All your services are running smoothly.</p>
        </div>
      <% else %>
        <%= for incident <- @incidents do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <div class="flex items-start justify-between">
                <div class="flex-1">
                  <div class="flex items-center gap-3 mb-2">
                    <div class={["w-3 h-3 rounded-full", incident_status_color(incident.status)]}>
                    </div>
                    <h3 class="font-semibold text-lg">{incident.monitor.name}</h3>
                    <div class={["badge", incident_status_badge(incident.status)]}>
                      {incident_status_text(incident.status)}
                    </div>
                  </div>

                  <p class="text-base-content/70 mb-3">
                    {if incident.cause, do: incident.cause, else: "No cause specified"}
                  </p>

                  <div class="flex items-center gap-4 text-sm text-base-content/60">
                    <span>Started: {format_datetime(incident.started_at)}</span>
                    <%= if incident.resolved_at do %>
                      <span>Resolved: {format_datetime(incident.resolved_at)}</span>
                      <span>Duration: {format_duration(incident.duration)}</span>
                    <% else %>
                      <span>Ongoing: {duration_since(incident.started_at)}</span>
                    <% end %>
                    <span>Updates: {length(incident.incident_updates)}</span>
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/dashboard/incidents/#{incident.id}"}
                    class="btn btn-sm btn-primary"
                  >
                    View Details
                  </.link>
                  <%= if incident.status == "ongoing" do %>
                    <button
                      phx-click="resolve_incident"
                      phx-value-id={incident.id}
                      class="btn btn-sm btn-success"
                      data-confirm="Are you sure you want to mark this incident as resolved?"
                    >
                      Resolve
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_incident_details(assigns) do
    ~H"""
    <!-- Incident Details -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Main Details -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Incident Summary -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-4">
              <div class={["w-4 h-4 rounded-full", incident_status_color(@incident.status)]}></div>
              <h2 class="text-xl font-semibold">{@incident.monitor.name}</h2>
              <div class={["badge", incident_status_badge(@incident.status)]}>
                {incident_status_text(@incident.status)}
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div>
                <span class="font-medium">Monitor:</span> {@incident.monitor.url}
              </div>
              <div>
                <span class="font-medium">Started:</span> {format_datetime(@incident.started_at)}
              </div>
              <%= if @incident.resolved_at do %>
                <div>
                  <span class="font-medium">Resolved:</span> {format_datetime(@incident.resolved_at)}
                </div>
                <div>
                  <span class="font-medium">Duration:</span> {format_duration(@incident.duration)}
                </div>
              <% else %>
                <div class="md:col-span-2">
                  <span class="font-medium">Ongoing for:</span> {duration_since(@incident.started_at)}
                </div>
              <% end %>
            </div>

            <%= if @incident.cause do %>
              <div class="mt-4 p-3 bg-base-200 rounded">
                <span class="font-medium">Cause:</span> {@incident.cause}
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Updates Timeline -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title mb-4">Incident Updates</h3>

            <%= if Enum.empty?(@incident.incident_updates) do %>
              <p class="text-base-content/70 py-8 text-center">No updates posted yet</p>
            <% else %>
              <div class="space-y-4">
                <%= for update <- Enum.sort_by(@incident.incident_updates, & &1.posted_at, {:desc, DateTime}) do %>
                  <div class="border-l-4 border-primary pl-4 py-2">
                    <div class="flex items-center gap-2 mb-2">
                      <div class={["badge badge-sm", IncidentUpdate.status_color(update.status)]}>
                        {IncidentUpdate.status_text(update.status)}
                      </div>
                      <span class="text-sm text-base-content/60">
                        {format_datetime(update.posted_at)}
                      </span>
                    </div>
                    <h4 class="font-medium mb-1">{update.title}</h4>
                    <p class="text-base-content/80">{update.description}</p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Sidebar -->
      <div class="space-y-6">
        <!-- Actions -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title mb-4">Actions</h3>
            <div class="space-y-2">
              <%= if @incident.status == "ongoing" do %>
                <button
                  phx-click="resolve_incident"
                  phx-value-id={@incident.id}
                  class="btn btn-success btn-block"
                  data-confirm="Are you sure you want to mark this incident as resolved?"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> Mark as Resolved
                </button>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Add Update Form -->
        <%= if @incident.status == "ongoing" do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h3 class="card-title mb-4">Post Update</h3>

              <form phx-submit="add_update" phx-change="validate_update" class="space-y-4">
                <.input
                  field={@incident_update[:status]}
                  type="select"
                  label="Status"
                  options={IncidentUpdate.status_options()}
                  required
                />

                <.input
                  field={@incident_update[:title]}
                  type="text"
                  label="Update Title"
                  placeholder="Brief description of the update"
                  required
                />

                <.input
                  field={@incident_update[:description]}
                  type="textarea"
                  label="Description"
                  placeholder="Detailed information about this update"
                  rows="4"
                  required
                />

                <button type="submit" class="btn btn-primary btn-block">
                  Post Update
                </button>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp incident_status_color("ongoing"), do: "bg-error"
  defp incident_status_color("resolved"), do: "bg-success"
  defp incident_status_color(_), do: "bg-base-content/30"

  defp incident_status_badge("ongoing"), do: "badge-error"
  defp incident_status_badge("resolved"), do: "badge-success"
  defp incident_status_badge(_), do: "badge-neutral"

  defp incident_status_text("ongoing"), do: "Ongoing"
  defp incident_status_text("resolved"), do: "Resolved"
  defp incident_status_text(_), do: "Unknown"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      seconds < 86400 -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
      true -> "#{div(seconds, 86400)}d #{div(rem(seconds, 86400), 3600)}h"
    end
  end

  defp duration_since(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at)
    |> format_duration()
  end
end
