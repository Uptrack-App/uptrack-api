defmodule Uptrack.Alerting.TelegramAlert do
  @moduledoc """
  Handles Telegram notifications for incidents.

  Telegram uses a Bot API to send messages:
  https://core.telegram.org/bots/api
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @telegram_api_base "https://api.telegram.org"

  @doc """
  Sends an incident alert to Telegram.
  """
  def send_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    case get_config(channel) do
      {:ok, bot_token, chat_id} ->
        message = build_incident_message(incident, monitor)
        send_telegram_message(bot_token, chat_id, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a resolution alert to Telegram.
  """
  def send_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    case get_config(channel) do
      {:ok, bot_token, chat_id} ->
        message = build_resolution_message(incident, monitor)
        send_telegram_message(bot_token, chat_id, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a "still down" reminder to Telegram.
  """
  def send_incident_reminder(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    case get_config(channel) do
      {:ok, bot_token, chat_id} ->
        message = build_reminder_message(incident, monitor)
        send_telegram_message(bot_token, chat_id, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a test alert to verify the Telegram bot is configured correctly.
  """
  def send_test_alert(%AlertChannel{} = channel) do
    case get_config(channel) do
      {:ok, bot_token, chat_id} ->
        message = """
        *Test Alert*

        This is a test notification from Uptrack\\.

        If you received this, your Telegram integration is working correctly\\!
        """

        send_telegram_message(bot_token, chat_id, message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_config(%AlertChannel{config: config}) do
    bot_token = config["bot_token"]
    chat_id = config["chat_id"]

    cond do
      is_nil(bot_token) or bot_token == "" ->
        {:error, "No Telegram bot token configured"}

      is_nil(chat_id) or chat_id == "" ->
        {:error, "No Telegram chat ID configured"}

      bot_token == "uptrack_managed" ->
        case Application.get_env(:uptrack, :telegram_bot_token) do
          nil -> {:error, "Uptrack Telegram bot not configured"}
          token -> {:ok, token, to_string(chat_id)}
        end

      true ->
        {:ok, bot_token, to_string(chat_id)}
    end
  end

  defp build_incident_message(incident, monitor) do
    cause = escape_markdown(incident.cause || "Unknown")
    name = escape_markdown(monitor.name)
    url = escape_markdown(monitor.url)

    """
    🚨 *MONITOR DOWN*

    *Monitor:* #{name}
    *URL:* `#{url}`
    *Started:* #{format_datetime(incident.started_at)}
    *Cause:* #{cause}

    \\#uptrack \\#incident
    """
  end

  defp build_resolution_message(incident, monitor) do
    name = escape_markdown(monitor.name)
    url = escape_markdown(monitor.url)

    """
    ✅ *MONITOR RESOLVED*

    *Monitor:* #{name}
    *URL:* `#{url}`
    *Downtime:* #{format_duration(incident.duration)}
    *Resolved:* #{format_datetime(incident.resolved_at)}

    \\#uptrack \\#resolved
    """
  end

  defp build_reminder_message(incident, monitor) do
    name = escape_markdown(monitor.name)
    url = escape_markdown(monitor.url)
    elapsed = DateTime.diff(DateTime.utc_now(), incident.started_at)

    """
    ⏰ *STILL DOWN*

    *Monitor:* #{name}
    *URL:* `#{url}`
    *Down for:* #{format_duration(elapsed)}
    *Started:* #{format_datetime(incident.started_at)}

    \\#uptrack \\#stilldown
    """
  end

  defp send_telegram_message(bot_token, chat_id, message) do
    url = "#{@telegram_api_base}/bot#{bot_token}/sendMessage"

    payload = %{
      chat_id: chat_id,
      text: message,
      parse_mode: "MarkdownV2",
      disable_web_page_preview: true
    }

    case Req.post(url, json: payload) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        Logger.info("Telegram notification sent successfully")
        {:ok, "sent"}

      {:ok, %{status: 200, body: %{"ok" => false, "description" => desc}}} ->
        Logger.error("Telegram API error: #{desc}")
        {:error, desc}

      {:ok, %{status: 429, body: body}} ->
        retry_after = get_in(body, ["parameters", "retry_after"]) || 30
        Logger.warning("Telegram rate limited, retry after #{retry_after}s")
        {:error, "rate_limited"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Telegram notification failed: #{status} - #{inspect(body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send Telegram notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Telegram MarkdownV2 requires escaping special characters
  defp escape_markdown(nil), do: "Unknown"

  defp escape_markdown(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("_", "\\_")
    |> String.replace("*", "\\*")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("~", "\\~")
    |> String.replace("`", "\\`")
    |> String.replace(">", "\\>")
    |> String.replace("#", "\\#")
    |> String.replace("+", "\\+")
    |> String.replace("-", "\\-")
    |> String.replace("=", "\\=")
    |> String.replace("|", "\\|")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace(".", "\\.")
    |> String.replace("!", "\\!")
  end

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(datetime) do
    escape_markdown(Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p UTC"))
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
