defmodule Uptrack.Alerting.MattermostAlert do
  @moduledoc """
  Handles Mattermost notifications for incidents.

  Mattermost incoming webhooks accept the same JSON payload format as Slack
  (text, attachments, fields, actions). This module delegates to the same
  payload builders but posts to a Mattermost webhook URL.
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    with {:ok, url} <- get_webhook_url(channel) do
      payload = %{
        text: "🚨 Monitor Alert: #{monitor.name} is DOWN",
        attachments: [
          %{
            color: "#D00000",
            fields: [
              %{title: "Monitor", value: monitor.name, short: true},
              %{title: "URL", value: monitor.url, short: true},
              %{title: "Started", value: Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC"), short: true},
              %{title: "Cause", value: incident.cause || "Unknown", short: true}
            ]
          }
        ]
      }

      post_message(url, payload)
    end
  end

  def send_resolution_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    with {:ok, url} <- get_webhook_url(channel) do
      payload = %{
        text: "✅ Monitor Resolved: #{monitor.name} is back UP",
        attachments: [
          %{
            color: "#2EB67D",
            fields: [
              %{title: "Monitor", value: monitor.name, short: true},
              %{title: "URL", value: monitor.url, short: true},
              %{title: "Downtime", value: format_duration(incident.duration), short: true},
              %{title: "Resolved", value: Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC"), short: true}
            ]
          }
        ]
      }

      post_message(url, payload)
    end
  end

  def send_test_alert(%AlertChannel{} = channel) do
    with {:ok, url} <- get_webhook_url(channel) do
      payload = %{
        text: "Test notification from Uptrack",
        attachments: [
          %{
            color: "#2EB67D",
            fields: [
              %{title: "Status", value: "Working", short: true},
              %{title: "Time", value: Calendar.strftime(DateTime.utc_now(), "%B %d, %Y at %I:%M %p UTC"), short: true}
            ],
            text: "If you received this, your Mattermost integration is working correctly!"
          }
        ]
      }

      post_message(url, payload)
    end
  end

  defp get_webhook_url(%{config: %{"webhook_url" => url}}) when is_binary(url) and url != "", do: {:ok, url}
  defp get_webhook_url(_), do: {:error, "No Mattermost webhook URL configured"}

  defp post_message(url, payload) do
    case Req.post(url, json: payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Mattermost notification sent successfully")
        {:ok, "sent"}

      {:ok, %{status: status}} ->
        Logger.error("Mattermost notification failed with status: #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send Mattermost notification: #{inspect(reason)}")
        {:error, reason}
    end
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
