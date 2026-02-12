defmodule Uptrack.Alerting.SlackAlert do
  @moduledoc """
  Handles Slack notifications for incidents.
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @doc """
  Sends an incident alert to Slack.
  """
  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Slack webhook URL configured"}
    else
      payload = build_incident_payload(incident, monitor)
      send_slack_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a resolution alert to Slack.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Slack webhook URL configured"}
    else
      payload = build_resolution_payload(incident, monitor)
      send_slack_message(webhook_url, payload)
    end
  end

  @doc """
  Sends a test alert to verify the Slack webhook is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    webhook_url = channel.config["webhook_url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No Slack webhook URL configured"}
    else
      payload = %{
        text: "Test notification from Uptrack",
        attachments: [
          %{
            color: "good",
            fields: [
              %{
                title: "Status",
                value: "Working",
                short: true
              },
              %{
                title: "Time",
                value: Calendar.strftime(DateTime.utc_now(), "%B %d, %Y at %I:%M %p UTC"),
                short: true
              }
            ],
            text: "If you received this, your Slack integration is working correctly!"
          }
        ]
      }

      send_slack_message(webhook_url, payload)
    end
  end

  defp build_incident_payload(incident, monitor) do
    %{
      text: "🚨 Monitor Alert: #{monitor.name} is DOWN",
      attachments: [
        %{
          color: "danger",
          fields: [
            %{
              title: "Monitor",
              value: monitor.name,
              short: true
            },
            %{
              title: "URL",
              value: monitor.url,
              short: true
            },
            %{
              title: "Started",
              value: Calendar.strftime(incident.started_at, "%B %d, %Y at %I:%M %p UTC"),
              short: true
            },
            %{
              title: "Cause",
              value: incident.cause || "Unknown",
              short: true
            }
          ],
          actions: [
            %{
              type: "button",
              text: "View Details",
              url: "#{app_url()}/dashboard/monitors/#{monitor.id}"
            }
          ]
        }
      ]
    }
  end

  defp build_resolution_payload(incident, monitor) do
    duration_text = format_duration(incident.duration)

    %{
      text: "✅ Monitor Resolved: #{monitor.name} is back UP",
      attachments: [
        %{
          color: "good",
          fields: [
            %{
              title: "Monitor",
              value: monitor.name,
              short: true
            },
            %{
              title: "URL",
              value: monitor.url,
              short: true
            },
            %{
              title: "Downtime",
              value: duration_text,
              short: true
            },
            %{
              title: "Resolved",
              value: Calendar.strftime(incident.resolved_at, "%B %d, %Y at %I:%M %p UTC"),
              short: true
            }
          ],
          actions: [
            %{
              type: "button",
              text: "View Details",
              url: "#{app_url()}/dashboard/monitors/#{monitor.id}"
            }
          ]
        }
      ]
    }
  end

  defp send_slack_message(webhook_url, payload) do
    case Req.post(webhook_url, json: payload) do
      {:ok, %{status: 200}} ->
        Logger.info("Slack notification sent successfully")
        {:ok, "sent"}

      {:ok, %{status: status}} ->
        Logger.error("Slack notification failed with status: #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send Slack notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")

  defp format_duration(nil), do: "Unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end
