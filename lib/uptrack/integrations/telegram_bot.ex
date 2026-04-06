defmodule Uptrack.Integrations.TelegramBot do
  @moduledoc """
  Uptrack's Telegram bot for one-click alert channel setup.

  Users click "Connect Telegram" → open deep link → add bot to group →
  bot receives /start with state token → creates alert channel automatically.

  ## Elixir Principles
  - Pure/impure separation: URL building + payload parsing are pure
  - SRP: this module handles bot logic only, Integrations context orchestrates
  - Let it crash: invalid webhooks return :ignore, Telegram retries on failure
  """

  require Logger

  @telegram_api "https://api.telegram.org"

  # --- Pure functions ---

  @doc "Builds a Telegram deep link URL for adding the bot to a group."
  def group_deep_link(state_token) do
    "https://t.me/#{bot_username()}?startgroup=#{state_token}"
  end

  @doc "Builds a Telegram deep link URL for starting a DM with the bot."
  def dm_deep_link(state_token) do
    "https://t.me/#{bot_username()}?start=#{state_token}"
  end

  @doc """
  Parses a Telegram webhook payload and extracts the /start command + state token.

  Returns {:ok, %{chat_id, chat_title, state_token}} or :ignore.
  """
  def parse_connect_command(payload) do
    with %{"message" => message} <- payload,
         %{"text" => text, "chat" => chat} <- message do
      case extract_start_token(text) do
        nil ->
          if text == "/start" or text == "/start@#{bot_username()}" do
            {:bare_start, chat["id"]}
          else
            :ignore
          end

        state_token ->
          {:ok, %{
            chat_id: chat["id"],
            chat_title: chat["title"] || chat["first_name"] || "Telegram",
            chat_type: chat["type"],
            state_token: state_token
          }}
      end
    else
      _ -> :ignore
    end
  end

  @doc "Validates the webhook secret header matches our configured secret."
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

  @doc """
  Registers the webhook URL with Telegram.

  Call once on app startup or config change.
  """
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

  # --- Private helpers ---

  defp extract_start_token(text) do
    case String.split(text, " ", parts: 2) do
      ["/start", token] -> String.trim(token)
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
