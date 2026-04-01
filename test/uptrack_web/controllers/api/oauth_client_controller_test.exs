defmodule UptrackWeb.OAuthClientControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.OAuthFixtures

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/oauth-clients" do
    test "lists clients for organization", %{conn: conn, org: org} do
      oauth_client_fixture(org.id, name: "Claude.ai")

      conn = get(conn, "/api/oauth-clients")
      response = json_response(conn, 200)

      assert length(response["clients"]) >= 1
    end

    test "does not show other org's clients", %{conn: conn} do
      other_org = Uptrack.MonitoringFixtures.organization_fixture()
      oauth_client_fixture(other_org.id, name: "Other Client")

      conn = get(conn, "/api/oauth-clients")
      response = json_response(conn, 200)

      names = Enum.map(response["clients"], & &1["name"])
      refute "Other Client" in names
    end
  end

  describe "POST /api/oauth-clients" do
    test "creates a new client", %{conn: conn} do
      conn = post(conn, "/api/oauth-clients", %{
        "name" => "Test Integration",
        "redirect_uris" => ["https://example.com/callback"]
      })

      response = json_response(conn, 201)
      assert response["name"] == "Test Integration"
      assert response["client_id"]
      assert response["client_secret"]
    end
  end

  describe "DELETE /api/oauth-clients/:id" do
    test "deletes a client", %{conn: conn, org: org} do
      client = oauth_client_fixture(org.id)

      conn = delete(conn, "/api/oauth-clients/#{client.id}")
      assert json_response(conn, 200)["deleted"] == true
    end
  end
end
