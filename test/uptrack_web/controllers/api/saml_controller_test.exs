defmodule UptrackWeb.Api.SamlControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Organizations

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/auth/sso/status" do
    test "returns not configured for new org", %{conn: conn} do
      conn = get(conn, "/api/auth/sso/status")
      response = json_response(conn, 200)
      assert response["configured"] == false
      assert response["enforced"] == false
    end
  end

  describe "GET /api/auth/sso/config" do
    test "returns null when not configured", %{conn: conn} do
      conn = get(conn, "/api/auth/sso/config")
      assert json_response(conn, 200)["data"] == nil
    end
  end

  describe "POST /api/auth/sso/config" do
    test "rejects on free plan", %{conn: conn} do
      conn = post(conn, "/api/auth/sso/config", %{
        "entity_id" => "https://idp.example.com",
        "sso_url" => "https://idp.example.com/sso",
        "certificate" => "cert-data"
      })

      assert json_response(conn, 402)["error"]["message"] =~ "Business"
    end

    test "configures SSO on business plan", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "business"})

      conn = post(conn, "/api/auth/sso/config", %{
        "entity_id" => "https://idp.example.com",
        "sso_url" => "https://idp.example.com/sso",
        "certificate" => "cert-data"
      })

      assert json_response(conn, 200)["ok"] == true

      # Verify config is stored
      config_conn = get(conn, "/api/auth/sso/config")
      data = json_response(config_conn, 200)["data"]
      assert data["entity_id"] == "https://idp.example.com"
      assert data["has_certificate"] == true
    end
  end

  describe "DELETE /api/auth/sso/config" do
    test "removes SSO config", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "business"})

      post(conn, "/api/auth/sso/config", %{
        "entity_id" => "https://idp.del.com",
        "sso_url" => "https://idp.del.com/sso",
        "certificate" => "cert"
      })

      conn = delete(conn, "/api/auth/sso/config")
      assert json_response(conn, 200)["ok"] == true

      status_conn = get(conn, "/api/auth/sso/status")
      assert json_response(status_conn, 200)["configured"] == false
    end
  end
end
