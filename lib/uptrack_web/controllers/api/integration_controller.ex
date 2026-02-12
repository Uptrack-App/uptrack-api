defmodule UptrackWeb.Api.IntegrationController do
  use UptrackWeb, :controller

  alias Uptrack.Integrations

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Initiates Slack OAuth flow.
  GET /api/integrations/slack/auth
  """
  def slack_auth(conn, _params) do
    user = conn.assigns.current_user
    auth_url = Integrations.slack_auth_url(user.organization_id, user.id)

    json(conn, %{auth_url: auth_url})
  end

  @doc """
  Handles Slack OAuth callback.
  GET /api/integrations/slack/callback
  """
  def slack_callback(conn, %{"code" => code, "state" => state}) do
    case Integrations.handle_slack_callback(code, state) do
      {:ok, alert_channel} ->
        redirect(conn,
          external: "#{frontend_url()}/dashboard/alerts?connected=slack&channel=#{alert_channel.id}"
        )

      {:error, :invalid_state} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=invalid_state")

      {:error, :state_expired} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=expired")

      {:error, {:slack_error, error}} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=#{error}")

      {:error, _} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=connection_failed")
    end
  end

  def slack_callback(conn, %{"error" => error}) do
    redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=#{error}")
  end

  @doc """
  Initiates Discord OAuth flow.
  GET /api/integrations/discord/auth
  """
  def discord_auth(conn, _params) do
    user = conn.assigns.current_user
    auth_url = Integrations.discord_auth_url(user.organization_id, user.id)

    json(conn, %{auth_url: auth_url})
  end

  @doc """
  Handles Discord OAuth callback.
  GET /api/integrations/discord/callback
  """
  def discord_callback(conn, %{"code" => code, "state" => state}) do
    case Integrations.handle_discord_callback(code, state) do
      {:ok, alert_channel} ->
        redirect(conn,
          external:
            "#{frontend_url()}/dashboard/alerts?connected=discord&channel=#{alert_channel.id}"
        )

      {:error, :invalid_state} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=invalid_state")

      {:error, :state_expired} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=expired")

      {:error, {:discord_error, _status, _body}} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=discord_error")

      {:error, _} ->
        redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=connection_failed")
    end
  end

  def discord_callback(conn, %{"error" => error}) do
    redirect(conn, external: "#{frontend_url()}/dashboard/alerts?error=#{error}")
  end

  defp frontend_url do
    Application.get_env(:uptrack, :frontend_url, "http://localhost:3000")
  end
end
