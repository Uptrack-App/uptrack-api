defmodule Uptrack.Integrations do
  @moduledoc """
  The Integrations context handles third-party connections.

  Supports:
  - Slack (incoming webhooks via OAuth2)
  - Discord (webhooks via OAuth2)
  - Telegram (deep link + webhook via @UptrackAppBot)

  All flows create alert channels automatically after successful authorization.
  """

  alias Uptrack.Monitoring
  alias Uptrack.Integrations.{OAuthState, TelegramBot}

  require Logger

  # ---------------------------------------------------------------------------
  # Slack OAuth
  # ---------------------------------------------------------------------------

  @slack_client_id System.get_env("SLACK_CLIENT_ID")
  @slack_client_secret System.get_env("SLACK_CLIENT_SECRET")


  @doc """
  Generates a Slack OAuth authorization URL.

  Stores state in ETS for CSRF protection.
  """
  def slack_auth_url(organization_id, user_id) do
    state = generate_state(organization_id, user_id, :slack)

    params = %{
      client_id: slack_client_id(),
      scope: "incoming-webhook",
      redirect_uri: slack_redirect_uri(),
      state: state
    }

    "https://slack.com/oauth/v2/authorize?" <> URI.encode_query(params)
  end

  @doc """
  Handles Slack OAuth callback.

  Exchanges code for access token, extracts webhook URL,
  and creates an alert channel automatically.
  """
  def handle_slack_callback(code, state) do
    with {:ok, %{organization_id: org_id, user_id: user_id}} <- verify_state(state, :slack),
         {:ok, token_response} <- exchange_slack_code(code),
         {:ok, alert_channel} <- create_slack_alert_channel(token_response, org_id, user_id) do
      {:ok, alert_channel}
    end
  end

  defp exchange_slack_code(code) do
    url = "https://slack.com/api/oauth.v2.access"

    body =
      URI.encode_query(%{
        client_id: slack_client_id(),
        client_secret: slack_client_secret(),
        code: code,
        redirect_uri: slack_redirect_uri()
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %{body: %{"ok" => false, "error" => error}}} ->
        {:error, {:slack_error, error}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp create_slack_alert_channel(token_response, organization_id, user_id) do
    webhook = token_response["incoming_webhook"]
    team_name = token_response["team"]["name"]
    channel_name = webhook["channel"]

    attrs = %{
      name: "Slack - #{team_name} ##{channel_name}",
      type: :slack,
      is_active: true,
      organization_id: organization_id,
      user_id: user_id,
      config: %{
        "webhook_url" => webhook["url"],
        "channel" => channel_name,
        "team_id" => token_response["team"]["id"],
        "team_name" => team_name,
        "configuration_url" => webhook["configuration_url"]
      }
    }

    Monitoring.create_alert_channel(attrs)
  end

  # ---------------------------------------------------------------------------
  # Discord OAuth
  # ---------------------------------------------------------------------------

  @discord_client_id System.get_env("DISCORD_CLIENT_ID")
  @discord_client_secret System.get_env("DISCORD_CLIENT_SECRET")


  @doc """
  Generates a Discord OAuth authorization URL.

  Uses the webhook.incoming scope to create webhooks.
  """
  def discord_auth_url(organization_id, user_id) do
    state = generate_state(organization_id, user_id, :discord)

    params = %{
      client_id: discord_client_id(),
      permissions: 0,
      scope: "webhook.incoming",
      redirect_uri: discord_redirect_uri(),
      response_type: "code",
      state: state
    }

    "https://discord.com/oauth2/authorize?" <> URI.encode_query(params)
  end

  @doc """
  Handles Discord OAuth callback.

  Exchanges code for webhook data and creates an alert channel.
  """
  def handle_discord_callback(code, state) do
    with {:ok, %{organization_id: org_id, user_id: user_id}} <- verify_state(state, :discord),
         {:ok, webhook_response} <- exchange_discord_code(code),
         {:ok, alert_channel} <- create_discord_alert_channel(webhook_response, org_id, user_id) do
      {:ok, alert_channel}
    end
  end

  defp exchange_discord_code(code) do
    url = "https://discord.com/api/oauth2/token"

    body =
      URI.encode_query(%{
        client_id: discord_client_id(),
        client_secret: discord_client_secret(),
        grant_type: "authorization_code",
        code: code,
        redirect_uri: discord_redirect_uri()
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:discord_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp create_discord_alert_channel(webhook_response, organization_id, user_id) do
    webhook = webhook_response["webhook"]

    webhook_url =
      "https://discord.com/api/webhooks/#{webhook["id"]}/#{webhook["token"]}"

    attrs = %{
      name: "Discord - #{webhook["name"]}",
      type: :discord,
      is_active: true,
      organization_id: organization_id,
      user_id: user_id,
      config: %{
        "webhook_url" => webhook_url,
        "webhook_id" => webhook["id"],
        "channel_id" => webhook["channel_id"],
        "guild_id" => webhook["guild_id"],
        "name" => webhook["name"]
      }
    }

    Monitoring.create_alert_channel(attrs)
  end

  # ---------------------------------------------------------------------------
  # Telegram (Deep Link + Webhook)
  # ---------------------------------------------------------------------------

  @doc """
  Generates a Telegram deep link URL for connecting a group or DM.

  Stores state in ETS for CSRF protection, same as Slack/Discord.
  Returns both group and DM links so the user can choose.
  """
  def telegram_auth_url(organization_id, user_id) do
    state = generate_state(organization_id, user_id, :telegram)

    %{
      group_url: TelegramBot.group_deep_link(state),
      dm_url: TelegramBot.dm_deep_link(state),
      state: state
    }
  end

  @doc """
  Handles the Telegram webhook payload when a user sends /start to the bot.

  Parses the command, verifies the state token, creates the alert channel,
  and sends a confirmation reply.
  """
  def handle_telegram_webhook(payload) do
    case TelegramBot.parse_connect_command(payload) do
      {:ok, %{chat_id: chat_id, chat_title: title, state_token: state_token}} ->
        with {:ok, %{organization_id: org_id, user_id: user_id}} <- verify_state(state_token, :telegram),
             {:ok, alert_channel} <- create_telegram_alert_channel(chat_id, title, org_id, user_id) do
          case TelegramBot.send_message(chat_id, "✅ <b>Connected to Uptrack!</b>\nThis chat will receive monitoring alerts.") do
            :ok -> :ok
            {:error, reason} -> Logger.warning("Failed to send Telegram confirmation: #{inspect(reason)}")
          end
          # Store result so frontend can poll for completion
          OAuthState.store("telegram_result:#{state_token}", %{
            channel_id: alert_channel.id,
            connected: true,
            expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
          })
          {:ok, alert_channel}
        else
          {:error, :invalid_state} ->
            TelegramBot.send_message(chat_id, "❌ Invalid or expired link. Please click \"Connect Telegram\" again in Uptrack.")
            {:error, :invalid_state}

          {:error, :state_expired} ->
            TelegramBot.send_message(chat_id, "❌ Link expired. Please click \"Connect Telegram\" again in Uptrack.")
            {:error, :state_expired}

          {:error, reason} ->
            Logger.error("TelegramBot connect failed: #{inspect(reason)}")
            TelegramBot.send_message(chat_id, "❌ Something went wrong. Please try again.")
            {:error, reason}
        end

      :ignore ->
        :ignore
    end
  end

  @doc """
  Checks if a Telegram connection has completed (frontend polls this).
  """
  def telegram_connection_status(state) do
    case OAuthState.get("telegram_result:#{state}") do
      %{connected: true, channel_id: channel_id} -> {:ok, channel_id}
      _ -> :pending
    end
  end

  defp create_telegram_alert_channel(chat_id, chat_title, organization_id, user_id) do
    attrs = %{
      name: "Telegram - #{chat_title}",
      type: :telegram,
      is_active: true,
      organization_id: organization_id,
      user_id: user_id,
      config: %{
        "bot_token" => "uptrack_managed",
        "chat_id" => to_string(chat_id)
      }
    }

    Monitoring.create_alert_channel(attrs)
  end

  # ---------------------------------------------------------------------------
  # OAuth State Management (CSRF Protection)
  # ---------------------------------------------------------------------------

  @state_ttl_seconds 600  # 10 minutes

  defp generate_state(organization_id, user_id, provider) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    OAuthState.store(state, %{
      organization_id: organization_id,
      user_id: user_id,
      provider: provider,
      expires_at: DateTime.add(DateTime.utc_now(), @state_ttl_seconds, :second)
    })

    state
  end

  defp verify_state(state, expected_provider) do
    case OAuthState.get_and_delete(state) do
      nil ->
        {:error, :invalid_state}

      %{provider: ^expected_provider, expires_at: expires_at} = data ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, data}
        else
          {:error, :state_expired}
        end

      _ ->
        {:error, :provider_mismatch}
    end
  end

  # ---------------------------------------------------------------------------
  # Config Helpers (with runtime fallback)
  # ---------------------------------------------------------------------------

  defp slack_client_id, do: Application.get_env(:uptrack, :slack_client_id) || @slack_client_id
  defp slack_client_secret, do: Application.get_env(:uptrack, :slack_client_secret) || @slack_client_secret
  defp slack_redirect_uri do
    Application.get_env(:uptrack, :slack_redirect_uri) ||
      Application.get_env(:uptrack, :app_url, "http://localhost:4000") <> "/api/integrations/slack/callback"
  end

  defp discord_client_id, do: Application.get_env(:uptrack, :discord_client_id) || @discord_client_id
  defp discord_client_secret, do: Application.get_env(:uptrack, :discord_client_secret) || @discord_client_secret

  defp discord_redirect_uri do
    Application.get_env(:uptrack, :discord_redirect_uri) ||
      Application.get_env(:uptrack, :app_url, "http://localhost:4000") <> "/api/integrations/discord/callback"
  end
end
