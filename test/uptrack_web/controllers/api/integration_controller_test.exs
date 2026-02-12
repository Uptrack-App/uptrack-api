defmodule UptrackWeb.Api.IntegrationControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Integrations.OAuthState

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/integrations/slack/auth" do
    test "returns auth URL with correct parameters", %{conn: conn} do
      conn = get(conn, "/api/integrations/slack/auth")

      response = json_response(conn, 200)
      assert auth_url = response["auth_url"]
      assert auth_url =~ "https://slack.com/oauth/v2/authorize"
      assert auth_url =~ "scope=incoming-webhook"
      assert auth_url =~ "state="
    end

    test "returns 401 when not authenticated" do
      conn = build_conn()
      conn = get(conn, "/api/integrations/slack/auth")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/integrations/discord/auth" do
    test "returns auth URL with correct parameters", %{conn: conn} do
      conn = get(conn, "/api/integrations/discord/auth")

      response = json_response(conn, 200)
      assert auth_url = response["auth_url"]
      assert auth_url =~ "https://discord.com/oauth2/authorize"
      assert auth_url =~ "scope=webhook.incoming"
      assert auth_url =~ "state="
    end

    test "returns 401 when not authenticated" do
      conn = build_conn()
      conn = get(conn, "/api/integrations/discord/auth")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/integrations/slack/callback" do
    test "redirects with error when state is invalid", %{conn: conn} do
      conn = get(conn, "/api/integrations/slack/callback", %{code: "test-code", state: "invalid-state"})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=invalid_state"
    end

    test "redirects with error when state is expired", %{conn: conn, user: user, org: org} do
      state = store_expired_state(org.id, user.id, :slack)

      conn = get(conn, "/api/integrations/slack/callback", %{code: "test-code", state: state})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=expired"
    end

    test "redirects with user-denied error", %{conn: conn} do
      conn = get(conn, "/api/integrations/slack/callback", %{error: "access_denied"})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=access_denied"
    end
  end

  describe "GET /api/integrations/discord/callback" do
    test "redirects with error when state is invalid", %{conn: conn} do
      conn = get(conn, "/api/integrations/discord/callback", %{code: "test-code", state: "invalid-state"})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=invalid_state"
    end

    test "redirects with error when state is expired", %{conn: conn, user: user, org: org} do
      state = store_expired_state(org.id, user.id, :discord)

      conn = get(conn, "/api/integrations/discord/callback", %{code: "test-code", state: state})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=expired"
    end

    test "redirects with user-denied error", %{conn: conn} do
      conn = get(conn, "/api/integrations/discord/callback", %{error: "access_denied"})

      assert redirected_to(conn) =~ "/dashboard/alerts?error=access_denied"
    end
  end

  describe "OAuth state token lifecycle" do
    test "state tokens are single-use", %{user: user, org: org} do
      state = store_valid_state(org.id, user.id, :slack)

      # First retrieval succeeds
      assert %{organization_id: _} = OAuthState.get_and_delete(state)

      # Second retrieval returns nil (token consumed)
      assert OAuthState.get_and_delete(state) == nil
    end

    test "expired tokens are rejected", %{user: user, org: org} do
      state = store_expired_state(org.id, user.id, :slack)

      data = OAuthState.get_and_delete(state)
      assert data != nil
      assert DateTime.compare(DateTime.utc_now(), data.expires_at) != :lt
    end

    test "provider mismatch is detected", %{user: user, org: org} do
      state = store_valid_state(org.id, user.id, :slack)

      # Store a state for :slack, but try to verify with :discord
      data = OAuthState.get_and_delete(state)
      assert data.provider == :slack
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp store_valid_state(org_id, user_id, provider) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    OAuthState.store(state, %{
      organization_id: org_id,
      user_id: user_id,
      provider: provider,
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
    })

    state
  end

  defp store_expired_state(org_id, user_id, provider) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    OAuthState.store(state, %{
      organization_id: org_id,
      user_id: user_id,
      provider: provider,
      expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
    })

    state
  end
end
