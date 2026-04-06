defmodule Uptrack.Integrations.TelegramBot do
  @moduledoc """
  Uptrack's Telegram bot for one-click alert channel setup.

  Supports DM, groups, and channels via a unified flow:
  1. User clicks "Connect Telegram" → gets a short code (e.g. A3X9)
  2. Adds @UptrackAppBot to group/channel OR opens DM
  3. Sends /connect CODE
  4. Bot verifies code → creates alert channel → confirms

  ## Elixir Principles
  - Pure/impure separation: payload parsing + code generation are pure
  - SRP: bot logic only, Integrations context orchestrates
  - Let it crash: invalid webhooks return :ignore
  """

  require Logger

  @telegram_api "https://api.telegram.org"

  # --- Pure functions ---

  @doc "Generates a short human-readable connect code (6 chars, uppercase alphanumeric)."
  def generate_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> binary_part(0, 6)
    |> String.upcase()
  end

  @doc """
  Parses a Telegram webhook payload for /connect or /start commands.

  Returns:
  - {:connect, %{chat_id, chat_title, code}} — user sent /connect CODE
  - {:start, %{chat_id, chat_title, token}} — user clicked deep link (DM)
  - {:bare_start, chat_id} — user sent /start without params
  - :ignore — not a relevant message
  """
  def parse_command(payload) do
    with %{"message" => message} <- payload,
         %{"text" => text, "chat" => chat} <- message do
      chat_info = %{
        chat_id: chat["id"],
        chat_title: chat["title"] || chat["first_name"] || "Telegram",
        chat_type: chat["type"]
      }

      cond do
        # /connect CODE — works in DM, groups, and channels
        match?("/connect" <> _, text) ->
          case extract_param(text, "/connect") do
            nil -> :ignore
            code -> {:connect, Map.put(chat_info, :code, String.upcase(code))}
          end

        # /start TOKEN — from deep link (DM only)
        match?("/start " <> _, text) ->
          case extract_param(text, "/start") do
            nil -> :ignore
            token -> {:start, Map.put(chat_info, :token, token)}
          end

        # Bare /start — reply with chat ID for manual setup
        text == "/start" or text == "/start@#{bot_username()}" ->
          {:bare_start, chat_info}

        true ->
          :ignore
      end
    else
      _ -> :ignore
    end
  end

  @doc "Validates the webhook secret header."
  def valid_secret?(header_value) when is_binary(header_value) do
    case webhook_secret() do
      nil -> false
      secret -> :crypto.hash_equals(header_value, secret)
    end
  end

  def valid_secret?(_), do: false

  # --- Impure functions (Telegram API calls) ---

  @doc "Sends a message to a Telegram chat."
  def send_message(chat_id, text) do
    url = "#{@telegram_api}/bot#{bot_token()}/sendMessage"

    case Req.post(url, json: %{
      chat_id: chat_id,
      text: text,
      parse_mode: "HTML"
    }) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} ->
        Logger.warning("TelegramBot.send_message failed: HTTP #{status} #{inspect(body)}")
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        Logger.warning("TelegramBot.send_message error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Registers the webhook URL with Telegram."
  def register_webhook do
    url = "#{@telegram_api}/bot#{bot_token()}/setWebhook"
    webhook_url = app_url() <> "/api/integrations/telegram/webhook"

    case Req.post(url, json: %{
      url: webhook_url,
      secret_token: webhook_secret(),
      allowed_updates: ["message"]
    }) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        Logger.info("TelegramBot: webhook registered at #{webhook_url}")
        :ok

      {:ok, %{body: body}} ->
        Logger.error("TelegramBot: webhook registration failed: #{inspect(body)}")
        {:error, body}

      {:error, reason} ->
        Logger.error("TelegramBot: webhook registration error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Builds a deep link URL for DM (used as fallback)."
  def dm_deep_link(state_token) do
    "https://t.me/#{bot_username()}?start=#{state_token}"
  end

  # --- Private helpers ---

  defp extract_param(text, command) do
    bot = bot_username()
    text
    |> String.replace("#{command}@#{bot}", command)
    |> String.split(" ", parts: 2)
    |> case do
      [^command, param] -> String.trim(param)
      _ -> nil
    end
  end

  defp bot_token, do: Application.get_env(:uptrack, :telegram_bot_token)
  defp bot_username, do: Application.get_env(:uptrack, :telegram_bot_username, "UptrackAppBot")
  defp webhook_secret, do: Application.get_env(:uptrack, :telegram_webhook_secret)

  defp app_url do
    Application.get_env(:uptrack, :app_url, "http://localhost:4000")
  end
end
