defmodule UptrackWeb.Api.AnalyticsControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/analytics/dashboard" do
    test "returns dashboard overview stats", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/dashboard")
      response = json_response(conn, 200)

      assert is_map(response["stats"])
      assert is_number(response["overall_uptime"]) or is_nil(response["overall_uptime"])
      assert response["period_days"] == 30
    end

    test "accepts custom days parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/dashboard?days=7")
      response = json_response(conn, 200)

      assert response["period_days"] == 7
    end

    test "defaults to 30 days for invalid parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/dashboard?days=invalid")
      response = json_response(conn, 200)

      assert response["period_days"] == 30
    end

    test "clamps days to valid range", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/dashboard?days=999")
      response = json_response(conn, 200)

      assert response["period_days"] == 30
    end
  end

  describe "GET /api/analytics/monitors/:monitor_id" do
    test "returns monitor analytics for owned monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(%{user_id: user.id, organization_id: org.id})

      conn = get(conn, ~p"/api/analytics/monitors/#{monitor.id}")
      response = json_response(conn, 200)

      assert response["monitor_id"] == to_string(monitor.id)
      assert response["period_days"] == 30
      assert is_list(response["uptime_chart"])
      assert is_list(response["response_times"])
      assert is_map(response["incident_stats"])
    end

    test "returns 404 for non-existent monitor", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/monitors/00000000-0000-0000-0000-000000000000")
      response = json_response(conn, 404)

      assert response["error"] =~ "not found"
    end

    test "accepts custom days parameter", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(%{user_id: user.id, organization_id: org.id})

      conn = get(conn, ~p"/api/analytics/monitors/#{monitor.id}?days=14")
      response = json_response(conn, 200)

      assert response["period_days"] == 14
    end
  end

  describe "GET /api/analytics/organization/trends" do
    test "returns organization-wide trends", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/organization/trends")
      response = json_response(conn, 200)

      assert response["period_days"] == 30
      assert is_number(response["overall_uptime"]) or is_nil(response["overall_uptime"])
      assert is_list(response["uptime_trends"])
      assert is_list(response["incident_frequency"])
      assert is_list(response["top_offenders"])
    end

    test "accepts custom days parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/organization/trends?days=90")
      response = json_response(conn, 200)

      assert response["period_days"] == 90
    end
  end

  describe "authentication" do
    test "returns 401 for unauthenticated requests", %{conn: _conn} do
      # Build a fresh conn without auth
      conn = Phoenix.ConnTest.build_conn()

      conn = get(conn, ~p"/api/analytics/dashboard")
      assert json_response(conn, 401)
    end
  end
end
