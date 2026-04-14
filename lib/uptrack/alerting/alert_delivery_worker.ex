defmodule Uptrack.Alerting.AlertDeliveryWorker do
  @moduledoc """
  Oban worker for delivering alert notifications with automatic retries.

  Each alert channel delivery is enqueued as a separate job, allowing
  independent retries with exponential backoff. Failed deliveries retry
  up to 5 times over ~30 minutes.

  Supported channel types: email, slack, discord, telegram.
  """

  use Oban.Worker,
    queue: :email_critical,
    max_attempts: 5,
    priority: 1

  alias Uptrack.Alerting
  alias Uptrack.Alerting.{
    EmailAlert,
    SlackAlert,
    DiscordAlert,
    TelegramAlert,
    DeliveryTracker
  }

  alias Uptrack.Monitoring
  alias Uptrack.Accounts
  alias Uptrack.Metrics.Writer
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "channel_id" => channel_id,
      "incident_id" => incident_id,
      "monitor_id" => monitor_id,
      "event_type" => event_type
    } = args

    channel = Alerting.get_alert_channel!(channel_id)
    incident = Monitoring.get_incident!(incident_id)
    monitor = Monitoring.get_monitor!(monitor_id)
    user = Accounts.get_user!(monitor.user_id)

    delivery_attrs = %{
      channel_type: channel.type,
      event_type: event_type,
      incident_id: incident.id,
      monitor_id: monitor.id,
      alert_channel_id: channel.id,
      organization_id: monitor.organization_id
    }

    start = System.monotonic_time(:millisecond)
    result = dispatch_alert(channel, incident, monitor, user, event_type)
    duration_ms = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, _} ->
        DeliveryTracker.record_success(delivery_attrs)
        Writer.write_notification_delivery(channel.type, "delivered", duration_ms, monitor.organization_id)
        :ok

      {:delayed, _} ->
        DeliveryTracker.record_skipped(delivery_attrs, "delayed by notification preferences")
        Writer.write_notification_delivery(channel.type, "skipped", duration_ms, monitor.organization_id)
        :ok

      {:error, reason} ->
        DeliveryTracker.record_failure(delivery_attrs, inspect(reason))
        Writer.write_notification_delivery(channel.type, "failed", duration_ms, monitor.organization_id)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 15s, 60s, 240s, 960s (~16 min total)
    trunc(:math.pow(4, attempt) * 15)
  end

  defp dispatch_alert(channel, incident, monitor, user, "incident_created") do
    case channel.type do
      "email" -> EmailAlert.send_incident_alert(channel, incident, monitor, user)
      "slack" -> SlackAlert.send_incident_alert(channel, incident, monitor)
      "discord" -> DiscordAlert.send_incident_alert(channel, incident, monitor)
      "telegram" -> TelegramAlert.send_incident_alert(channel, incident, monitor)

      type ->
        Logger.error("Unsupported alert channel type: #{type}")
        {:error, :unsupported_type}
    end
  end

  defp dispatch_alert(channel, incident, monitor, user, "incident_resolved") do
    case channel.type do
      "email" -> EmailAlert.send_resolution_alert(channel, incident, monitor, user)
      "slack" -> SlackAlert.send_resolution_alert(channel, incident, monitor)
      "discord" -> DiscordAlert.send_resolution_alert(channel, incident, monitor)
      "telegram" -> TelegramAlert.send_resolution_alert(channel, incident, monitor)

      type ->
        Logger.error("Unsupported alert channel type: #{type}")
        {:error, :unsupported_type}
    end
  end

  defp dispatch_alert(channel, incident, monitor, user, "incident_reminder") do
    case channel.type do
      "email" -> EmailAlert.send_incident_reminder(channel, incident, monitor, user)
      "slack" -> SlackAlert.send_incident_reminder(channel, incident, monitor)
      "discord" -> DiscordAlert.send_incident_reminder(channel, incident, monitor)
      "telegram" -> TelegramAlert.send_incident_reminder(channel, incident, monitor)

      type ->
        Logger.error("Unsupported alert channel type for reminder: #{type}")
        {:error, :unsupported_type}
    end
  end
end
