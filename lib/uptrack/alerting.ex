defmodule Uptrack.Alerting do
  @moduledoc """
  Context for managing alerts and notifications.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  alias Uptrack.Alerting.{EmailAlert, SlackAlert, DiscordAlert, TelegramAlert, TeamsAlert, TwilioAlert, WebhookAlert}
  alias Uptrack.Monitoring.{StatusPage, StatusPageMonitor, StatusPageSubscriber}
  alias Uptrack.Emails.SubscriberEmail
  alias Uptrack.Accounts.User
  alias Uptrack.Mailer
  require Logger

  @doc """
  Sends alerts for a new incident based on the monitor's alert configuration.
  """
  def send_incident_alerts(%Incident{} = incident, %Monitor{} = monitor) do
    Logger.info("Sending alerts for incident #{incident.id} on monitor #{monitor.name}")

    # Get user and check notification preferences
    user = AppRepo.get!(User, monitor.user_id)

    unless User.should_notify?(user, :monitor_down) do
      Logger.info("User #{user.id} has disabled monitor down notifications")
      [{:skipped_user_preferences, user.id}]
    else
      # Check quiet hours
      if in_quiet_hours?(user) do
        Logger.info("Skipping incident alert for user #{user.id} due to quiet hours")
        [{:skipped_quiet_hours, user.id}]
      else
        # Get organization's alert channels
        alert_channels = list_active_alert_channels(monitor.organization_id)

        # Get monitor-specific alert settings
        monitor_alert_contacts = monitor.alert_contacts || %{}

        # Send alerts through all configured channels
        results =
          Enum.map(alert_channels, fn channel ->
            if should_send_alert?(channel, monitor_alert_contacts, user) do
              send_alert(channel, incident, monitor, user)
            else
              {:skipped, channel.id}
            end
          end)

        # Log results
        successful = Enum.count(results, &match?({:ok, _}, &1))
        total = length(results)
        Logger.info("Sent #{successful}/#{total} alerts for incident #{incident.id}")

        results
      end
    end
  end

  @doc """
  Sends resolution notifications for a resolved incident.
  """
  def send_resolution_alerts(%Incident{} = incident, %Monitor{} = monitor) do
    Logger.info(
      "Sending resolution alerts for incident #{incident.id} on monitor #{monitor.name}"
    )

    # Get user and check notification preferences
    user = AppRepo.get!(User, monitor.user_id)

    unless User.should_notify?(user, :monitor_up) do
      Logger.info("User #{user.id} has disabled monitor up notifications")
      [{:skipped_user_preferences, user.id}]
    else
      # Check quiet hours (but allow critical resolution notifications)
      # Resolution notifications are typically allowed even during quiet hours

      # Get organization's alert channels
      alert_channels = list_active_alert_channels(monitor.organization_id)

      # Get monitor-specific alert settings
      monitor_alert_contacts = monitor.alert_contacts || %{}

      # Send resolution alerts through configured channels
      results =
        Enum.map(alert_channels, fn channel ->
          if should_send_alert?(channel, monitor_alert_contacts, user) do
            send_resolution_alert(channel, incident, monitor, user)
          else
            {:skipped, channel.id}
          end
        end)

      # Log results
      successful = Enum.count(results, &match?({:ok, _}, &1))
      total = length(results)
      Logger.info("Sent #{successful}/#{total} resolution alerts for incident #{incident.id}")

      results
    end
  end

  @doc """
  Returns the list of active alert channels for an organization.
  """
  def list_active_alert_channels(organization_id) do
    AlertChannel
    |> where([ac], ac.organization_id == ^organization_id and ac.is_active == true)
    |> order_by([ac], asc: ac.name)
    |> AppRepo.all()
  end

  @doc """
  Creates an alert channel.
  """
  def create_alert_channel(attrs) do
    %AlertChannel{}
    |> AlertChannel.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates an alert channel.
  """
  def update_alert_channel(%AlertChannel{} = alert_channel, attrs) do
    alert_channel
    |> AlertChannel.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes an alert channel.
  """
  def delete_alert_channel(%AlertChannel{} = alert_channel) do
    AppRepo.delete(alert_channel)
  end

  @doc """
  Gets a single alert channel.
  """
  def get_alert_channel!(id), do: AppRepo.get!(AlertChannel, id)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking alert channel changes.
  """
  def change_alert_channel(%AlertChannel{} = alert_channel, attrs \\ %{}) do
    AlertChannel.changeset(alert_channel, attrs)
  end

  # Private functions

  defp should_send_alert?(channel, monitor_alert_contacts, user) do
    # Check if this alert channel is enabled for this monitor
    # If monitor_alert_contacts is empty, send to all channels
    monitor_enabled =
      case Map.get(monitor_alert_contacts, channel.type) do
        # No specific config, send alert
        nil -> true
        # Explicitly disabled
        false -> false
        # Explicitly enabled
        true -> true
        %{"enabled" => enabled} -> enabled
        # Default to enabled
        _ -> true
      end

    # Check user notification preferences for email channels
    if channel.type == "email" do
      prefs = User.get_notification_preferences(user)
      email_enabled = prefs["email_enabled"]
      monitor_enabled && email_enabled
    else
      monitor_enabled
    end
  end

  defp in_quiet_hours?(user) do
    prefs = User.get_notification_preferences(user)

    if prefs["quiet_hours_enabled"] do
      now = DateTime.utc_now()
      current_time = Time.new!(now.hour, now.minute, 0)

      start_time = parse_time(prefs["quiet_hours_start"])
      end_time = parse_time(prefs["quiet_hours_end"])

      if start_time && end_time do
        if Time.compare(start_time, end_time) == :gt do
          # Quiet hours span midnight (e.g., 22:00 to 08:00)
          Time.compare(current_time, start_time) != :lt ||
            Time.compare(current_time, end_time) != :gt
        else
          # Quiet hours within same day (e.g., 12:00 to 14:00)
          Time.compare(current_time, start_time) != :lt &&
            Time.compare(current_time, end_time) != :gt
        end
      else
        false
      end
    else
      false
    end
  end

  defp parse_time(time_string) when is_binary(time_string) do
    case String.split(time_string, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             {:ok, time} <- Time.new(hour, minute, 0) do
          time
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_time(_), do: nil

  defp send_alert(channel, incident, monitor, user) do
    case channel.type do
      "email" ->
        EmailAlert.send_incident_alert(channel, incident, monitor, user)

      "slack" ->
        SlackAlert.send_incident_alert(channel, incident, monitor)

      "discord" ->
        DiscordAlert.send_incident_alert(channel, incident, monitor)

      "telegram" ->
        TelegramAlert.send_incident_alert(channel, incident, monitor)

      "teams" ->
        TeamsAlert.send_incident_alert(channel, incident, monitor)

      "webhook" ->
        WebhookAlert.send_incident_alert(channel, incident, monitor)

      "sms" ->
        TwilioAlert.send_sms_incident_alert(channel, incident, monitor)

      "phone" ->
        TwilioAlert.send_phone_incident_alert(channel, incident, monitor)

      type ->
        Logger.error("Unknown alert channel type: #{type}")
        {:error, :unknown_type}
    end
  rescue
    e ->
      Logger.error("Error sending alert via #{channel.type}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp send_resolution_alert(channel, incident, monitor, user) do
    case channel.type do
      "email" ->
        EmailAlert.send_resolution_alert(channel, incident, monitor, user)

      "slack" ->
        SlackAlert.send_resolution_alert(channel, incident, monitor)

      "discord" ->
        DiscordAlert.send_resolution_alert(channel, incident, monitor)

      "telegram" ->
        TelegramAlert.send_resolution_alert(channel, incident, monitor)

      "teams" ->
        TeamsAlert.send_resolution_alert(channel, incident, monitor)

      "webhook" ->
        WebhookAlert.send_resolution_alert(channel, incident, monitor)

      "sms" ->
        TwilioAlert.send_sms_resolution_alert(channel, incident, monitor)

      "phone" ->
        TwilioAlert.send_phone_resolution_alert(channel, incident, monitor)

      type ->
        Logger.error("Unknown alert channel type: #{type}")
        {:error, :unknown_type}
    end
  rescue
    e ->
      Logger.error("Error sending resolution alert via #{channel.type}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc """
  Sends a test alert to verify the channel is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    case channel.type do
      "email" ->
        EmailAlert.send_test_alert(channel)

      "slack" ->
        SlackAlert.send_test_alert(channel)

      "discord" ->
        DiscordAlert.send_test_alert(channel)

      "telegram" ->
        TelegramAlert.send_test_alert(channel)

      "teams" ->
        TeamsAlert.send_test_alert(channel)

      "webhook" ->
        WebhookAlert.send_test_alert(channel)

      "sms" ->
        TwilioAlert.send_test_sms(channel)

      "phone" ->
        TwilioAlert.send_test_call(channel)

      type ->
        {:error, "Unknown alert channel type: #{type}"}
    end
  rescue
    e ->
      Logger.error("Error sending test alert via #{channel.type}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  # Status page subscriber notifications

  @doc """
  Notifies all subscribers of status pages that include this monitor about a new incident.
  """
  def notify_subscribers_incident(%Incident{} = incident, %Monitor{} = monitor) do
    status_pages = get_status_pages_for_monitor(monitor.id)

    results =
      Enum.flat_map(status_pages, fn status_page ->
        if status_page.allow_subscriptions do
          subscribers = get_verified_subscribers(status_page.id)

          Enum.map(subscribers, fn subscriber ->
            send_subscriber_incident_email(subscriber, status_page, incident, monitor)
          end)
        else
          []
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    total = length(results)
    Logger.info("Sent #{successful}/#{total} subscriber notifications for incident #{incident.id}")

    results
  end

  @doc """
  Notifies all subscribers of status pages that include this monitor about a resolved incident.
  """
  def notify_subscribers_resolution(%Incident{} = incident, %Monitor{} = monitor) do
    status_pages = get_status_pages_for_monitor(monitor.id)

    results =
      Enum.flat_map(status_pages, fn status_page ->
        if status_page.allow_subscriptions do
          subscribers = get_verified_subscribers(status_page.id)

          Enum.map(subscribers, fn subscriber ->
            send_subscriber_resolution_email(subscriber, status_page, incident, monitor)
          end)
        else
          []
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    total = length(results)
    Logger.info("Sent #{successful}/#{total} subscriber resolution notifications for incident #{incident.id}")

    results
  end

  defp get_status_pages_for_monitor(monitor_id) do
    StatusPageMonitor
    |> where([spm], spm.monitor_id == ^monitor_id)
    |> join(:inner, [spm], sp in StatusPage, on: sp.id == spm.status_page_id)
    |> where([spm, sp], sp.is_public == true)
    |> select([spm, sp], sp)
    |> AppRepo.all()
  end

  defp get_verified_subscribers(status_page_id) do
    StatusPageSubscriber
    |> where([s], s.status_page_id == ^status_page_id and s.verified == true)
    |> AppRepo.all()
  end

  defp send_subscriber_incident_email(subscriber, status_page, incident, monitor) do
    email = SubscriberEmail.incident_email(subscriber, status_page, incident, monitor)

    case Mailer.deliver(email) do
      {:ok, _} ->
        Logger.debug("Sent incident notification to subscriber #{subscriber.email}")
        {:ok, subscriber.email}

      {:error, reason} ->
        Logger.error("Failed to send incident notification to #{subscriber.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_subscriber_resolution_email(subscriber, status_page, incident, monitor) do
    email = SubscriberEmail.resolution_email(subscriber, status_page, incident, monitor)

    case Mailer.deliver(email) do
      {:ok, _} ->
        Logger.debug("Sent resolution notification to subscriber #{subscriber.email}")
        {:ok, subscriber.email}

      {:error, reason} ->
        Logger.error("Failed to send resolution notification to #{subscriber.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
