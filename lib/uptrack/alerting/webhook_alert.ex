defmodule Uptrack.Alerting.WebhookAlert do
  @moduledoc """
  Handles webhook notifications for incidents.

  ## Configuration

  The webhook alert channel config supports:
  - `url` (required) - The webhook URL to POST to
  - `secret` (optional) - Secret for HMAC-SHA256 signature in `X-Uptrack-Signature` header
  - `headers` (optional) - Additional headers to send with the request

  ## Security

  When a `secret` is configured, each request includes an `X-Uptrack-Signature` header
  containing an HMAC-SHA256 signature of the request body. Receivers can verify:

  ```elixir
  expected = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  signature = "sha256=" <> expected
  ```
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
      send_webhook(channel, payload)
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
      send_webhook(channel, payload)
    end
  end

  @doc """
  Sends a test alert to verify the webhook is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    webhook_url = channel.config["url"]

    if is_nil(webhook_url) or webhook_url == "" do
      {:error, "No webhook URL configured"}
    else
      payload = %{
        event: "test",
        message: "This is a test notification from Uptrack",
        channel_name: channel.name,
        status: "working",
        timestamp: DateTime.utc_now()
      }

      send_webhook(channel, payload)
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

  defp send_webhook(%AlertChannel{config: config}, payload) do
    webhook_url = config["url"]
    body = Jason.encode!(payload)

    headers =
      [
        {"Content-Type", "application/json"},
        {"User-Agent", "Uptrack-Monitor/1.0"},
        {"X-Uptrack-Event", payload[:event] || payload["event"] || "unknown"}
      ]
      |> maybe_add_signature(body, config["secret"])
      |> maybe_add_custom_headers(config["headers"])

    case Req.post(webhook_url, body: body, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Webhook notification sent successfully to #{webhook_url}")
        {:ok, "sent"}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Webhook notification failed with status: #{status}, body: #{inspect(response_body)}")
        {:error, "HTTP #{status}"}

      {:error, %{reason: :timeout}} ->
        Logger.error("Webhook notification timed out: #{webhook_url}")
        {:error, "timeout"}

      {:error, reason} ->
        Logger.error("Failed to send webhook notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_signature(headers, _body, nil), do: headers
  defp maybe_add_signature(headers, _body, ""), do: headers

  defp maybe_add_signature(headers, body, secret) when is_binary(secret) do
    signature = compute_signature(body, secret)
    [{"X-Uptrack-Signature", "sha256=#{signature}"} | headers]
  end

  defp compute_signature(body, secret) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  defp maybe_add_custom_headers(headers, nil), do: headers
  defp maybe_add_custom_headers(headers, custom) when is_map(custom) do
    custom_headers =
      Enum.map(custom, fn {key, value} ->
        {to_string(key), to_string(value)}
      end)

    headers ++ custom_headers
  end
  defp maybe_add_custom_headers(headers, _), do: headers
end
