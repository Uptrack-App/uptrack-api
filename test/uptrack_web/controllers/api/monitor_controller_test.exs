defmodule UptrackWeb.Api.MonitorControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/monitors" do
    test "lists monitors for the current organization", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, ~p"/api/monitors")

      response = json_response(conn, 200)
      assert [monitor_data] = response["data"]
      assert monitor_data["id"] == monitor.id
      assert monitor_data["name"] == monitor.name
      assert monitor_data["url"] == monitor.url
    end

    test "does not return monitors from other organizations", %{conn: conn} do
      # Create a monitor in a different org
      _other_monitor = monitor_fixture()

      conn = get(conn, ~p"/api/monitors")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "returns 401 without authentication", %{conn: _conn} do
      conn =
        build_conn()
        |> get(~p"/api/monitors")

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "Authentication"
    end
  end

  describe "POST /api/monitors" do
    test "creates a monitor with smart defaults from URL", %{conn: conn} do
      conn = post(conn, ~p"/api/monitors", %{"url" => "https://example.com"})

      response = json_response(conn, 201)
      assert response["data"]["url"] == "https://example.com"
      assert response["data"]["status"] == "active"
      assert response["data"]["monitor_type"] in ["http", "https"]
    end

    test "allows overriding smart defaults", %{conn: conn} do
      conn =
        post(conn, ~p"/api/monitors", %{
          "url" => "https://example.com",
          "name" => "Custom Name",
          "interval" => 600
        })

      response = json_response(conn, 201)
      assert response["data"]["name"] == "Custom Name"
      assert response["data"]["interval"] == 600
    end
  end

  describe "GET /api/monitors/:id" do
    test "returns a specific monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, ~p"/api/monitors/#{monitor.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == monitor.id
    end

    test "returns 404 for monitor in different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn = get(conn, ~p"/api/monitors/#{other_monitor.id}")

      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent monitor", %{conn: conn} do
      conn = get(conn, ~p"/api/monitors/#{Uniq.UUID.uuid7()}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/monitors/:id" do
    test "updates the monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = patch(conn, ~p"/api/monitors/#{monitor.id}", %{"name" => "Updated Name"})

      response = json_response(conn, 200)
      assert response["data"]["name"] == "Updated Name"
    end

    test "returns 404 when updating monitor from different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn = patch(conn, ~p"/api/monitors/#{other_monitor.id}", %{"name" => "Hacked"})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/monitors/:id" do
    test "deletes the monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = delete(conn, ~p"/api/monitors/#{monitor.id}")

      assert conn.status == 204
    end

    test "returns 404 when deleting monitor from different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn = delete(conn, ~p"/api/monitors/#{other_monitor.id}")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/monitors/:monitor_id/checks" do
    test "returns checks for a monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, ~p"/api/monitors/#{monitor.id}/checks")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end

    test "returns 404 for monitor in different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn = get(conn, ~p"/api/monitors/#{other_monitor.id}/checks")

      assert json_response(conn, 404)
    end

    test "respects limit parameter", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, ~p"/api/monitors/#{monitor.id}/checks", %{"limit" => "5"})

      response = json_response(conn, 200)
      assert length(response["data"]) <= 5
    end
  end

  describe "POST /api/monitors/smart-defaults" do
    test "returns smart defaults for a URL", %{conn: conn} do
      conn = post(conn, ~p"/api/monitors/smart-defaults", %{"url" => "https://example.com"})

      response = json_response(conn, 200)
      assert response["data"]["url"] == "https://example.com"
      assert is_list(response["data"]["suggested_regions"])
    end
  end
end
