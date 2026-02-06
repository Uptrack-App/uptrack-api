defmodule Uptrack.Alerting.TeamsAlert do
  @moduledoc """
  Handles Microsoft Teams notifications for incidents.

  Teams uses Adaptive Cards via Incoming Webhooks:
  https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @doc """
  Sends an incident alert to Microsoft Teams.
  """
  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Teams webhook URL configured"}
    else
      payload = build_incident_payload(incident, monitor)
      send_teams_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a resolution alert to Microsoft Teams.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Teams webhook URL configured"}
    else
      payload = build_resolution_payload(incident, monitor)
      send_teams_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a test alert to verify the Teams webhook is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Teams webhook URL configured"}
    else
      payload = %{
        "@type" => "MessageCard",
        "@context" => "http://schema.org/extensions",
        themeColor: "0076D7",
        summary: "Test Alert from Uptrack",
        sections: [
          %{
            activityTitle: "Test Alert",
            activitySubtitle: "This is a test notification from Uptrack",
            facts: [
              %{name: "Status", value: "Working"},
              %{name: "Time", value: Calendar.strftime(DateTime.utc_now(), "%B %d, %Y at %I:%M %p UTC")}
            ],
            text: "If you received this, your Microsoft Teams integration is working correctly!"
          }
        ]
      }

      send_teams_message(webhook_url, payload)
    end
  end

  defp build_incident_payload(incident, monitor) do
    %{
      "@type" => "MessageCard",
      "@context" => "http://schema.org/extensions",
      themeColor: "FF0000",
      summary: "Monitor DOWN: #{monitor.name}",
      sections: [
        %{
          activityTitle: "Monitor DOWN",
          activitySubtitle: monitor.name,
          activityImage: nil,
          facts: [
            %{name: "Monitor", value: monitor.name},
            %{name: "URL", value: monitor.url},
            %{name: "Started", value: format_datetime(incident.started_at)},
            %{name: "Cause", value: incident.cause || "Unknown"}
          ],
          markdown: true
        }
      ],
      potentialAction: [
        %{
          "@type" => "OpenUri",
          name: "View Details",
          targets: [
            %{os: "default", uri: build_monitor_url(monitor)}
          ]
        }
      ]
    }
  end

  defp build_resolution_payload(incident, monitor) do
    %{
      "@type" => "MessageCard",
      "@context" => "http://schema.org/extensions",
      themeColor: "00FF00",
      summary: "Monitor UP: #{monitor.name}",
      sections: [
        %{
          activityTitle: "Monitor UP",
          activitySubtitle: "#{monitor.name} is responding again",
          facts: [
            %{name: "Monitor", value: monitor.name},
            %{name: "URL", value: monitor.url},
            %{name: "Downtime", value: format_duration(incident.duration)},
            %{name: "Resolved", value: format_datetime(incident.resolved_at)}
          ],
          markdown: true
        }
      ],
      potentialAction: [
        %{
          "@type" => "OpenUri",
          name: "View Details",
          targets: [
            %{os: "default", uri: build_monitor_url(monitor)}
          ]
        }
      ]
    }
  end

  defp send_teams_message(webhook_url, payload) do
    case Req.post(webhook_url, json: payload) do
      {:ok, %{status: 200}} ->
        Logger.info("Teams notification sent successfully")
        {:ok, "sent"}

      {:ok, %{status: 202}} ->
        Logger.info("Teams notification accepted")
        {:ok, "sent"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Teams notification failed: #{status} - #{inspect(body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send Teams notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_monitor_url(monitor) do
    base_url = Application.get_env(:uptrack, :app_url, "http://localhost:4000")
    "#{base_url}/dashboard/monitors/#{monitor.id}"
  end

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p UTC")
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
