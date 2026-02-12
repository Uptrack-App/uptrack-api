defmodule UptrackWeb.Api.StatusPageControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/status-pages" do
    test "lists status pages", %{conn: conn, user: user, org: org} do
      _page = status_page_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, "/api/status-pages")

      response = json_response(conn, 200)
      assert [page] = response["data"]
      assert page["name"]
      assert page["slug"]
    end
  end

  describe "POST /api/status-pages" do
    test "creates a status page", %{conn: conn} do
      conn =
        post(conn, "/api/status-pages", %{
          "name" => "Acme Status",
          "slug" => "acme-status",
          "description" => "Service status for Acme Corp"
        })

      response = json_response(conn, 201)
      assert response["data"]["name"] == "Acme Status"
      assert response["data"]["slug"] == "acme-status"
      assert response["data"]["is_public"] == true
    end
  end

  describe "DELETE /api/status-pages/:id" do
    test "deletes own status page", %{conn: conn, user: user, org: org} do
      page = status_page_fixture(organization_id: org.id, user_id: user.id)

      conn = delete(conn, "/api/status-pages/#{page.id}")

      assert conn.status == 204
    end

    test "returns 404 for other org's page", %{conn: conn} do
      other = status_page_fixture()

      conn = delete(conn, "/api/status-pages/#{other.id}")

      assert json_response(conn, 404)
    end
  end
end
