defmodule Uptrack.Alerting.WebhookAlert do
  @moduledoc """
  Handles webhook notifications for incidents.
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @doc """
  Sends an incident alert via webhook.
  """
  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    webhook_url = channel.config["url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No webhook URL configured"}
    else
      payload = build_incident_payload(incident, monitor)
      send_webhook(webhook_url, payload)
    end
  end

  @doc """
  Sends a resolution alert via webhook.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    webhook_url = channel.config["url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No webhook URL configured"}
    else
      payload = build_resolution_payload(incident, monitor)
      send_webhook(webhook_url, payload)
    end
  end

  defp build_incident_payload(incident, monitor) do
    %{
      event: "incident.created",
      monitor: %{
        id: monitor.id,
        name: monitor.name,
        url: monitor.url,
        type: monitor.monitor_type
      },
      incident: %{
        id: incident.id,
        started_at: incident.started_at,
        cause: incident.cause,
        status: incident.status
      },
      timestamp: DateTime.utc_now()
    }
  end

  defp build_resolution_payload(incident, monitor) do
    %{
      event: "incident.resolved",
      monitor: %{
        id: monitor.id,
        name: monitor.name,
        url: monitor.url,
        type: monitor.monitor_type
      },
      incident: %{
        id: incident.id,
        started_at: incident.started_at,
        resolved_at: incident.resolved_at,
        duration: incident.duration,
        cause: incident.cause,
        status: incident.status
      },
      timestamp: DateTime.utc_now()
    }
  end

  defp send_webhook(webhook_url, payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "Uptrack-Monitor/1.0"}
    ]

    case Req.post(webhook_url, json: payload, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Webhook notification sent successfully to #{webhook_url}")
        {:ok, "sent"}

      {:ok, %{status: status}} ->
        Logger.error("Webhook notification failed with status: #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send webhook notification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
