defmodule Uptrack.Alerting.DiscordAlert do
  @moduledoc """
  Handles Discord notifications for incidents.

  Discord uses webhook embeds which have a different format from Slack.
  See: https://discord.com/developers/docs/resources/webhook
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @doc """
  Sends an incident alert to Discord.
  """
  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Discord webhook URL configured"}
    else
      payload = build_incident_payload(incident, monitor)
      send_discord_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a resolution alert to Discord.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Discord webhook URL configured"}
    else
      payload = build_resolution_payload(incident, monitor)
      send_discord_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a test alert to verify the Discord webhook is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Discord webhook URL configured"}
    else
      payload = %{
        content: "Test notification from Uptrack",
        embeds: [
          %{
            title: "Test Alert",
            description: "This is a test notification from Uptrack. If you received this, your Discord integration is working correctly!",
            color: 3_447_003,  # Blue
            timestamp: DateTime.to_iso8601(DateTime.utc_now()),
            footer: %{
              text: "Uptrack Monitoring"
            }
          }
        ]
      }

      send_discord_message(webhook_url, payload)
    end
  end

  defp build_incident_payload(incident, monitor) do
    %{
      content: "Monitor Alert: #{monitor.name} is DOWN",
      embeds: [
        %{
          title: "Monitor DOWN",
          description: "#{monitor.name} is not responding",
          color: 15_158_332,  # Red
          fields: [
            %{name: "Monitor", value: monitor.name, inline: true},
            %{name: "URL", value: monitor.url, inline: true},
            %{name: "Started", value: format_datetime(incident.started_at), inline: true},
            %{name: "Cause", value: incident.cause || "Unknown", inline: false}
          ],
          timestamp: DateTime.to_iso8601(incident.started_at),
          footer: %{
            text: "Uptrack Monitoring"
          }
        }
      ]
    }
  end

  defp build_resolution_payload(incident, monitor) do
    %{
      content: "Monitor Resolved: #{monitor.name} is back UP",
      embeds: [
        %{
          title: "Monitor UP",
          description: "#{monitor.name} is responding again",
          color: 3_066_993,  # Green
          fields: [
            %{name: "Monitor", value: monitor.name, inline: true},
            %{name: "URL", value: monitor.url, inline: true},
            %{name: "Downtime", value: format_duration(incident.duration), inline: true},
            %{name: "Resolved", value: format_datetime(incident.resolved_at), inline: true}
          ],
          timestamp: DateTime.to_iso8601(incident.resolved_at || DateTime.utc_now()),
          footer: %{
            text: "Uptrack Monitoring"
          }
        }
      ]
    }
  end

  defp send_discord_message(webhook_url, payload) do
    case Req.post(webhook_url, json: payload) do
      {:ok, %{status: status}} when status in [200, 204] ->
        Logger.info("Discord notification sent successfully")
        {:ok, "sent"}

      {:ok, %{status: 429, body: body}} ->
        retry_after = body["retry_after"] || 5
        Logger.warning("Discord rate limited, retry after #{retry_after}s")
        {:error, "rate_limited"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Discord notification failed: #{status} - #{inspect(body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send Discord notification: #{inspect(reason)}")
        {:error, reason}
    end
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
