defmodule UptrackWeb.Api.DashboardControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/dashboard/stats" do
    test "returns dashboard stats", %{conn: conn, user: user, org: org} do
      _monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, "/api/dashboard/stats")

      response = json_response(conn, 200)
      data = response["data"]
      assert data["total_monitors"] == 1
      assert data["active_monitors"] == 1
      assert data["ongoing_incidents"] == 0
      assert data["recent_incidents"] == 0
    end

    test "returns empty stats for new org", %{conn: conn} do
      conn = get(conn, "/api/dashboard/stats")

      response = json_response(conn, 200)
      assert response["data"]["total_monitors"] == 0
    end
  end
end
