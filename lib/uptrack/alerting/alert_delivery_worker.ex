defmodule Uptrack.Alerting.AlertDeliveryWorker do
  @moduledoc """
  Oban worker for delivering alert notifications with automatic retries.

  Each alert channel delivery is enqueued as a separate job, allowing
  independent retries with exponential backoff. Failed deliveries retry
  up to 5 times over ~30 minutes.
  """

  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    priority: 1

  alias Uptrack.Alerting
  alias Uptrack.Alerting.{
    EmailAlert,
    SlackAlert,
    DiscordAlert,
    TelegramAlert,
    TeamsAlert,
    TelnyxAlert,
    WebhookAlert,
    MattermostAlert,
    QuotaTracker,
    DeliveryTracker
  }

  alias Uptrack.Monitoring
  alias Uptrack.Organizations
  alias Uptrack.Accounts
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

    result = dispatch_alert(channel, incident, monitor, user, event_type)

    case result do
      {:ok, _} ->
        DeliveryTracker.record_success(delivery_attrs)
        :ok

      {:delayed, _} ->
        DeliveryTracker.record_skipped(delivery_attrs, "delayed by notification preferences")
        :ok

      {:error, reason} ->
        DeliveryTracker.record_failure(delivery_attrs, inspect(reason))
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
      "teams" -> TeamsAlert.send_incident_alert(channel, incident, monitor)
      "webhook" -> WebhookAlert.send_incident_alert(channel, incident, monitor)
      "sms" -> with_sms_quota(monitor.organization_id, fn -> TelnyxAlert.send_sms_incident_alert(channel, incident, monitor) end)
      "phone" -> with_sms_quota(monitor.organization_id, fn -> TelnyxAlert.send_phone_incident_alert(channel, incident, monitor) end)
      "mattermost" -> MattermostAlert.send_incident_alert(channel, incident, monitor)
      type ->
        Logger.error("Unknown alert channel type: #{type}")
        {:error, :unknown_type}
    end
  end

  defp dispatch_alert(channel, incident, monitor, user, "incident_resolved") do
    case channel.type do
      "email" -> EmailAlert.send_resolution_alert(channel, incident, monitor, user)
      "slack" -> SlackAlert.send_resolution_alert(channel, incident, monitor)
      "discord" -> DiscordAlert.send_resolution_alert(channel, incident, monitor)
      "telegram" -> TelegramAlert.send_resolution_alert(channel, incident, monitor)
      "teams" -> TeamsAlert.send_resolution_alert(channel, incident, monitor)
      "webhook" -> WebhookAlert.send_resolution_alert(channel, incident, monitor)
      "sms" -> with_sms_quota(monitor.organization_id, fn -> TelnyxAlert.send_sms_resolution_alert(channel, incident, monitor) end)
      "phone" -> with_sms_quota(monitor.organization_id, fn -> TelnyxAlert.send_phone_resolution_alert(channel, incident, monitor) end)
      "mattermost" -> MattermostAlert.send_resolution_alert(channel, incident, monitor)
      type ->
        Logger.error("Unknown alert channel type: #{type}")
        {:error, :unknown_type}
    end
  end

  defp with_sms_quota(organization_id, send_fn) do
    org = Organizations.get_organization(organization_id)
    plan = if org, do: org.plan, else: "free"

    case QuotaTracker.check_and_increment(organization_id, plan) do
      :ok ->
        send_fn.()

      {:error, :quota_exhausted} ->
        Logger.warning("SMS/call quota exhausted for org #{organization_id}, skipping delivery")
        {:error, :quota_exhausted}
    end
  end
end
