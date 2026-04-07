defmodule UptrackWeb.AlertChannelLive do
  use UptrackWeb, :live_view

  alias Uptrack.Alerting
  alias Uptrack.Monitoring.AlertChannel

  @impl true
  def mount(_params, _session, socket) do
    %{current_organization: org} = socket.assigns

    alert_channels = Alerting.list_active_alert_channels(org.id)

    socket =
      socket
      |> assign(:alert_channels, alert_channels)
      |> assign(:page_title, "Alert Channels")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Alert Channels")
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Alert Channel")
    |> assign(:alert_channel, %AlertChannel{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    alert_channel = Alerting.get_alert_channel!(id)

    socket
    |> assign(:page_title, "Edit Alert Channel")
    |> assign(:alert_channel, alert_channel)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    %{current_organization: org} = socket.assigns
    alert_channel = Alerting.get_alert_channel!(id)
    {:ok, _} = Alerting.delete_alert_channel(alert_channel)

    # Refresh the list
    alert_channels = Alerting.list_active_alert_channels(org.id)

    socket =
      socket
      |> assign(:alert_channels, alert_channels)
      |> put_flash(:info, "Alert channel deleted successfully")

    {:noreply, socket}
  end

  def handle_event("test_alert", %{"id" => id}, socket) do
    %{current_organization: org, current_user: user} = socket.assigns
    alert_channel = Alerting.get_alert_channel!(id)

    # Create test structs for testing
    test_monitor = %Uptrack.Monitoring.Monitor{
      id: nil,
      name: "Test Monitor",
      url: "https://example.com",
      organization_id: org.id,
      user_id: user.id,
      monitor_type: "http"
    }

    test_incident = %Uptrack.Monitoring.Incident{
      id: 999,
      started_at: DateTime.utc_now(),
      cause: "This is a test alert to verify your notification settings.",
      status: "ongoing"
    }

    case alert_channel.type do
      "email" ->
        case Uptrack.Alerting.EmailAlert.send_incident_alert(
               alert_channel,
               test_incident,
               test_monitor
             ) do
          {:ok, _} ->
            put_flash(socket, :info, "Test email sent successfully!")

          {:error, reason} ->
            put_flash(socket, :error, "Failed to send test email: #{reason}")
        end

      "slack" ->
        case Uptrack.Alerting.SlackAlert.send_incident_alert(
               alert_channel,
               test_incident,
               test_monitor
             ) do
          {:ok, _} ->
            put_flash(socket, :info, "Test Slack message sent successfully!")

          {:error, reason} ->
            put_flash(socket, :error, "Failed to send test Slack message: #{reason}")
        end

      _ ->
        put_flash(socket, :error, "Unknown alert channel type")
    end
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({UptrackWeb.AlertChannelLive.FormComponent, {:saved, _alert_channel}}, socket) do
    %{current_organization: org} = socket.assigns
    # Refresh the data when an alert channel is saved
    alert_channels = Alerting.list_active_alert_channels(org.id)

    socket =
      socket
      |> assign(:alert_channels, alert_channels)

    {:noreply, socket}
  end

  defp channel_icon("email"), do: "hero-envelope"
  defp channel_icon("slack"), do: "hero-chat-bubble-left-ellipsis"
  defp channel_icon("webhook"), do: "hero-globe-alt"
  defp channel_icon(_), do: "hero-bell"

  defp channel_description("email"), do: "Get notified via email"
  defp channel_description("slack"), do: "Send messages to Slack channel"
  defp channel_description("webhook"), do: "HTTP webhooks for custom integrations"
  defp channel_description(_), do: "Custom notification channel"
end
