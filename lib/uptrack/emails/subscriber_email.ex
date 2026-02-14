defmodule Uptrack.Emails.SubscriberEmail do
  @moduledoc """
  Email templates for status page subscribers.
  """

  import Swoosh.Email
  alias Uptrack.Monitoring.{StatusPage, StatusPageSubscriber, Monitor, Incident}
  require Logger

  @from_email {"Uptrack Status", "status@uptrack.app"}
  defp base_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")

  @doc """
  Sends a verification email to confirm subscription.
  """
  def verification_email(%StatusPageSubscriber{} = subscriber, %StatusPage{} = status_page) do
    verify_url = "#{base_url()}/api/subscribe/verify/#{subscriber.verification_token}"

    new()
    |> to(subscriber.email)
    |> from(@from_email)
    |> subject("Verify your subscription to #{status_page.name}")
    |> html_body(verification_html(status_page, verify_url))
    |> text_body(verification_text(status_page, verify_url))
  end

  @doc """
  Sends an incident notification to a subscriber.
  """
  def incident_email(%StatusPageSubscriber{} = subscriber, %StatusPage{} = status_page, %Incident{} = incident, %Monitor{} = monitor) do
    status_url = "#{base_url()}/status/#{status_page.slug}"
    unsubscribe_url = "#{base_url()}/api/subscribe/unsubscribe/#{subscriber.unsubscribe_token}"

    new()
    |> to(subscriber.email)
    |> from(@from_email)
    |> subject("Incident: #{monitor.name} is experiencing issues")
    |> html_body(incident_html(status_page, monitor, incident, status_url, unsubscribe_url))
    |> text_body(incident_text(status_page, monitor, incident, status_url, unsubscribe_url))
  end

  @doc """
  Sends a resolution notification to a subscriber.
  """
  def resolution_email(%StatusPageSubscriber{} = subscriber, %StatusPage{} = status_page, %Incident{} = incident, %Monitor{} = monitor) do
    status_url = "#{base_url()}/status/#{status_page.slug}"
    unsubscribe_url = "#{base_url()}/api/subscribe/unsubscribe/#{subscriber.unsubscribe_token}"
    duration_text = format_duration(incident.duration)

    new()
    |> to(subscriber.email)
    |> from(@from_email)
    |> subject("Resolved: #{monitor.name} is back online")
    |> html_body(resolution_html(status_page, monitor, incident, duration_text, status_url, unsubscribe_url))
    |> text_body(resolution_text(status_page, monitor, incident, duration_text, status_url, unsubscribe_url))
  end

  # Private templates

  defp verification_html(status_page, verify_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Verify your subscription</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #3b82f6; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; margin: 16px 0; font-weight: 600; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 12px; color: #666; text-align: center; }
            .link-fallback { color: #666; font-size: 14px; word-break: break-all; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>#{status_page.name}</h1>
            </div>
            <div class="content">
                <h2 style="margin-top: 0;">Verify Your Subscription</h2>
                <p>You requested to receive status updates for <strong>#{status_page.name}</strong>.</p>
                <p>Click the button below to confirm your subscription and start receiving incident notifications:</p>

                <div style="text-align: center;">
                    <a href="#{verify_url}" class="btn">Verify Subscription</a>
                </div>

                <p class="link-fallback">Or copy and paste this link into your browser:<br>#{verify_url}</p>

                <p style="color: #666; margin-top: 24px;">
                    If you didn't request this subscription, you can safely ignore this email.
                </p>
            </div>
            <div class="footer">
                <p>Powered by <a href="https://uptrack.app">Uptrack</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp verification_text(status_page, verify_url) do
    """
    Verify Your Subscription to #{status_page.name}

    You requested to receive status updates for #{status_page.name}.

    Click the link below to confirm your subscription and start receiving incident notifications:

    #{verify_url}

    If you didn't request this subscription, you can safely ignore this email.

    ---
    Powered by Uptrack
    """
  end

  defp incident_html(status_page, monitor, incident, status_url, unsubscribe_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Incident: #{monitor.name}</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #ef4444; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .alert-box { background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .info-table { width: 100%; border-collapse: collapse; margin: 16px 0; }
            .info-table td { padding: 8px 0; border-bottom: 1px solid #e5e5e5; }
            .info-table td:first-child { font-weight: 600; width: 120px; color: #666; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 16px 0; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 12px; color: #666; text-align: center; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>#{status_page.name}</h1>
            </div>
            <div class="content">
                <div class="alert-box">
                    <h2 style="margin-top: 0; color: #ef4444;">Service Incident</h2>
                    <p><strong>#{monitor.name}</strong> is currently experiencing issues.</p>
                </div>

                <table class="info-table">
                    <tr>
                        <td>Service:</td>
                        <td>#{monitor.name}</td>
                    </tr>
                    <tr>
                        <td>Started:</td>
                        <td>#{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}</td>
                    </tr>
                    #{if incident.cause do
                      "<tr><td>Details:</td><td>#{incident.cause}</td></tr>"
                    else
                      ""
                    end}
                </table>

                <div style="text-align: center;">
                    <a href="#{status_url}" class="btn">View Status Page</a>
                </div>

                <p style="color: #666;">You'll receive another email when this incident is resolved.</p>
            </div>
            <div class="footer">
                <p>You're receiving this because you subscribed to #{status_page.name} status updates.</p>
                <p><a href="#{unsubscribe_url}">Unsubscribe</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp incident_text(status_page, monitor, incident, status_url, unsubscribe_url) do
    """
    SERVICE INCIDENT - #{status_page.name}

    #{monitor.name} is currently experiencing issues.

    Service: #{monitor.name}
    Started: #{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}
    #{if incident.cause, do: "Details: #{incident.cause}", else: ""}

    View status page: #{status_url}

    You'll receive another email when this incident is resolved.

    ---
    You're receiving this because you subscribed to #{status_page.name} status updates.
    Unsubscribe: #{unsubscribe_url}
    """
  end

  defp resolution_html(status_page, monitor, incident, duration_text, status_url, unsubscribe_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Resolved: #{monitor.name}</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #10b981; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .success-box { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .info-table { width: 100%; border-collapse: collapse; margin: 16px 0; }
            .info-table td { padding: 8px 0; border-bottom: 1px solid #e5e5e5; }
            .info-table td:first-child { font-weight: 600; width: 120px; color: #666; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 16px 0; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 12px; color: #666; text-align: center; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>#{status_page.name}</h1>
            </div>
            <div class="content">
                <div class="success-box">
                    <h2 style="margin-top: 0; color: #10b981;">Incident Resolved</h2>
                    <p><strong>#{monitor.name}</strong> is now back online.</p>
                </div>

                <table class="info-table">
                    <tr>
                        <td>Service:</td>
                        <td>#{monitor.name}</td>
                    </tr>
                    <tr>
                        <td>Started:</td>
                        <td>#{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}</td>
                    </tr>
                    <tr>
                        <td>Resolved:</td>
                        <td>#{if incident.resolved_at, do: Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC"), else: "Unknown"}</td>
                    </tr>
                    <tr>
                        <td>Duration:</td>
                        <td>#{duration_text}</td>
                    </tr>
                </table>

                <div style="text-align: center;">
                    <a href="#{status_url}" class="btn">View Status Page</a>
                </div>
            </div>
            <div class="footer">
                <p>You're receiving this because you subscribed to #{status_page.name} status updates.</p>
                <p><a href="#{unsubscribe_url}">Unsubscribe</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp resolution_text(status_page, monitor, incident, duration_text, status_url, unsubscribe_url) do
    """
    INCIDENT RESOLVED - #{status_page.name}

    #{monitor.name} is now back online.

    Service: #{monitor.name}
    Started: #{Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC")}
    Resolved: #{if incident.resolved_at, do: Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC"), else: "Unknown"}
    Duration: #{duration_text}

    View status page: #{status_url}

    ---
    You're receiving this because you subscribed to #{status_page.name} status updates.
    Unsubscribe: #{unsubscribe_url}
    """
  end

  defp format_duration(nil), do: "Unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 ->
        "#{seconds} seconds"

      seconds < 3600 ->
        minutes = div(seconds, 60)
        "#{minutes} minutes"

      true ->
        hours = div(seconds, 3600)
        remaining_minutes = div(rem(seconds, 3600), 60)
        "#{hours} hours, #{remaining_minutes} minutes"
    end
  end
end
