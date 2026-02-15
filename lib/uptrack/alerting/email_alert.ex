defmodule Uptrack.Alerting.EmailAlert do
  @moduledoc """
  Handles email notifications for incidents.
  """

  import Swoosh.Email
  alias Uptrack.Mailer
  alias Uptrack.AppRepo
  alias Uptrack.Alerting.PendingNotification
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  alias Uptrack.Accounts.User
  require Logger

  @doc """
  Sends an incident alert email.
  """
  def send_incident_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor,
        user \\ nil
      ) do
    email_config = channel.config
    recipient_email = email_config["email"]

    if is_nil(recipient_email) or recipient_email == "" do
      {:error, "No email address configured"}
    else
      # Check notification frequency preferences if user is provided
      if user && should_delay_notification?(user, :incident_started) do
        Logger.info(
          "Delaying incident alert for user #{user.id} due to notification frequency settings"
        )

        queue_pending_notification(user, incident, monitor, recipient_email, "incident_created")
        {:delayed, recipient_email}
      else
        email =
          new()
          |> to(recipient_email)
          |> from({"Uptrack Monitoring", "alerts@uptrack.app"})
          |> subject("🚨 Alert: #{monitor.name} is DOWN")
          |> html_body(incident_html_body(incident, monitor))
          |> text_body(incident_text_body(incident, monitor))

        case Mailer.deliver(email) do
          {:ok, _metadata} ->
            Logger.info(
              "Incident alert email sent to #{recipient_email} for monitor #{monitor.name}"
            )

            {:ok, recipient_email}

          {:error, reason} ->
            Logger.error(
              "Failed to send incident alert email to #{recipient_email}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end
    end
  end

  @doc """
  Sends a resolution alert email.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor,
        user \\ nil
      ) do
    email_config = channel.config
    recipient_email = email_config["email"]

    if is_nil(recipient_email) or recipient_email == "" do
      {:error, "No email address configured"}
    else
      # Check notification frequency preferences if user is provided
      if user && should_delay_notification?(user, :incident_resolved) do
        Logger.info(
          "Delaying resolution alert for user #{user.id} due to notification frequency settings"
        )

        queue_pending_notification(user, incident, monitor, recipient_email, "incident_resolved")
        {:delayed, recipient_email}
      else
        duration_text = format_duration(incident.duration)

        email =
          new()
          |> to(recipient_email)
          |> from({"Uptrack Monitoring", "alerts@uptrack.app"})
          |> subject("✅ Resolved: #{monitor.name} is back UP")
          |> html_body(resolution_html_body(incident, monitor, duration_text))
          |> text_body(resolution_text_body(incident, monitor, duration_text))

        case Mailer.deliver(email) do
          {:ok, _metadata} ->
            Logger.info(
              "Resolution alert email sent to #{recipient_email} for monitor #{monitor.name}"
            )

            {:ok, recipient_email}

          {:error, reason} ->
            Logger.error(
              "Failed to send resolution alert email to #{recipient_email}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end
    end
  end

  @doc """
  Sends a test alert email to verify the email channel is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    email_config = channel.config
    recipient_email = email_config["email"]

    if is_nil(recipient_email) or recipient_email == "" do
      {:error, "No email address configured"}
    else
      email =
        new()
        |> to(recipient_email)
        |> from({"Uptrack Monitoring", "alerts@uptrack.app"})
        |> subject("Test Alert from Uptrack")
        |> html_body(test_html_body())
        |> text_body("This is a test notification from Uptrack. If you received this, your email integration is working correctly!")

      case Mailer.deliver(email) do
        {:ok, _metadata} ->
          Logger.info("Test alert email sent to #{recipient_email}")
          {:ok, recipient_email}

        {:error, reason} ->
          Logger.error("Failed to send test alert email to #{recipient_email}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp test_html_body do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Test Alert from Uptrack</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #3b82f6; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .success-box { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 14px; color: #666; text-align: center; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>✅ Test Alert</h1>
            </div>
            <div class="content">
                <div class="success-box">
                    <h2 style="margin-top: 0; color: #22c55e;">Your email integration is working!</h2>
                    <p>This is a test notification from Uptrack. If you received this, your email integration is configured correctly.</p>
                </div>
                <p>You can now receive incident alerts at this email address.</p>
            </div>
            <div class="footer">
                <p>Sent by <a href="https://uptrack.app">Uptrack</a> Monitoring</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  # Email templates

  defp incident_html_body(incident, monitor) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Alert: #{monitor.name} is DOWN</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #ef4444; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .alert-box { background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .info-table { width: 100%; border-collapse: collapse; margin: 16px 0; }
            .info-table td { padding: 8px 0; border-bottom: 1px solid #e5e5e5; }
            .info-table td:first-child { font-weight: 600; width: 120px; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 14px; color: #666; text-align: center; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 16px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🚨 Service Alert</h1>
            </div>
            <div class="content">
                <div class="alert-box">
                    <h2 style="margin-top: 0; color: #ef4444;">#{monitor.name} is DOWN</h2>
                    <p>Your monitor has detected that <strong>#{monitor.name}</strong> is currently experiencing issues.</p>
                </div>

                <table class="info-table">
                    <tr>
                        <td>Monitor:</td>
                        <td>#{monitor.name}</td>
                    </tr>
                    <tr>
                        <td>URL:</td>
                        <td>#{monitor.url}</td>
                    </tr>
                    <tr>
                        <td>Incident Started:</td>
                        <td>#{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}</td>
                    </tr>
                    #{if incident.cause do
      "<tr><td>Cause:</td><td>#{incident.cause}</td></tr>"
    else
      ""
    end}
                    <tr>
                        <td>Confirmed:</td>
                        <td>#{monitor.confirmation_threshold} consecutive checks failed</td>
                    </tr>
                </table>

                <a href="#{app_url()}/dashboard/monitors/#{monitor.id}" class="btn">View Monitor Details</a>

                <p style="margin-top: 24px; color: #666;">
                    This is an automated alert from Uptrack Monitoring. You'll receive another notification when the service is restored.
                </p>
            </div>
            <div class="footer">
                <p>Uptrack Monitoring • Powered by Phoenix LiveView</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp incident_text_body(incident, monitor) do
    """
    🚨 ALERT: #{monitor.name} is DOWN

    Your monitor has detected that #{monitor.name} is currently experiencing issues.

    Monitor Details:
    ---------------
    Name: #{monitor.name}
    URL: #{monitor.url}
    Incident Started: #{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}
    #{if incident.cause, do: "Cause: #{incident.cause}", else: ""}
    Confirmed: #{monitor.confirmation_threshold} consecutive checks failed

    You can view more details at: #{app_url()}/dashboard/monitors/#{monitor.id}

    This is an automated alert from Uptrack Monitoring. You'll receive another notification when the service is restored.

    ---
    Uptrack Monitoring
    """
  end

  defp resolution_html_body(incident, monitor, duration_text) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Resolved: #{monitor.name} is UP</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #10b981; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .success-box { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .info-table { width: 100%; border-collapse: collapse; margin: 16px 0; }
            .info-table td { padding: 8px 0; border-bottom: 1px solid #e5e5e5; }
            .info-table td:first-child { font-weight: 600; width: 120px; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 14px; color: #666; text-align: center; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 16px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>✅ Service Restored</h1>
            </div>
            <div class="content">
                <div class="success-box">
                    <h2 style="margin-top: 0; color: #10b981;">#{monitor.name} is back UP</h2>
                    <p>Great news! Your monitor has detected that <strong>#{monitor.name}</strong> is now responding normally.</p>
                </div>

                <table class="info-table">
                    <tr>
                        <td>Monitor:</td>
                        <td>#{monitor.name}</td>
                    </tr>
                    <tr>
                        <td>URL:</td>
                        <td>#{monitor.url}</td>
                    </tr>
                    <tr>
                        <td>Incident Started:</td>
                        <td>#{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}</td>
                    </tr>
                    <tr>
                        <td>Resolved:</td>
                        <td>#{Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC")}</td>
                    </tr>
                    <tr>
                        <td>Downtime:</td>
                        <td>#{duration_text}</td>
                    </tr>
                </table>

                <a href="#{app_url()}/dashboard/monitors/#{monitor.id}" class="btn">View Monitor Details</a>

                <p style="margin-top: 24px; color: #666;">
                    This incident has been automatically resolved. Thank you for your patience.
                </p>
            </div>
            <div class="footer">
                <p>Uptrack Monitoring • Powered by Phoenix LiveView</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp resolution_text_body(incident, monitor, duration_text) do
    """
    ✅ RESOLVED: #{monitor.name} is back UP

    Great news! Your monitor has detected that #{monitor.name} is now responding normally.

    Incident Details:
    ----------------
    Name: #{monitor.name}
    URL: #{monitor.url}
    Incident Started: #{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}
    Resolved: #{Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC")}
    Total Downtime: #{duration_text}

    You can view more details at: #{app_url()}/dashboard/monitors/#{monitor.id}

    This incident has been automatically resolved. Thank you for your patience.

    ---
    Uptrack Monitoring
    """
  end

  defp should_delay_notification?(user, notification_type) do
    prefs = User.get_notification_preferences(user)
    frequency = prefs["notification_frequency"]

    # Only delay for non-immediate frequencies
    # Critical alerts like incidents are typically sent immediately regardless
    case {frequency, notification_type} do
      {"immediate", _} -> false
      # Could implement hourly batching
      {"hourly", _} -> true
      # Could implement daily digest
      {"daily", _} -> true
      _ -> false
    end
  end

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")

  defp format_duration(nil), do: "Unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 ->
        "#{seconds} seconds"

      seconds < 3600 ->
        minutes = div(seconds, 60)
        remaining_seconds = rem(seconds, 60)
        "#{minutes} minutes, #{remaining_seconds} seconds"

      true ->
        hours = div(seconds, 3600)
        remaining_minutes = div(rem(seconds, 3600), 60)
        "#{hours} hours, #{remaining_minutes} minutes"
    end
  end

  defp queue_pending_notification(user, incident, monitor, recipient_email, event_type) do
    %PendingNotification{}
    |> PendingNotification.changeset(%{
      event_type: event_type,
      recipient_email: recipient_email,
      incident_id: incident.id,
      monitor_id: monitor.id,
      user_id: user.id,
      organization_id: monitor.organization_id
    })
    |> AppRepo.insert()
    |> case do
      {:ok, _} ->
        Logger.info("Queued pending #{event_type} notification for #{recipient_email}")

      {:error, reason} ->
        Logger.error("Failed to queue pending notification: #{inspect(reason)}")
    end
  end
end
