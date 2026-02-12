defmodule UptrackWeb.Api.HeartbeatControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "POST /api/heartbeat/:token" do
    test "records heartbeat for valid token", %{conn: conn} do
      token = Uptrack.Monitoring.Heartbeat.generate_token()

      monitor =
        monitor_fixture(%{
          monitor_type: "heartbeat",
          settings: %{"token" => token, "expected_interval_seconds" => 3600}
        })

      conn = post(conn, ~p"/api/heartbeat/#{token}")

      response = json_response(conn, 200)
      assert response["ok"] == true
      assert response["monitor"]["id"] == monitor.id
    end

    test "accepts heartbeat with status payload", %{conn: conn} do
      token = Uptrack.Monitoring.Heartbeat.generate_token()

      _monitor =
        monitor_fixture(%{
          monitor_type: "heartbeat",
          settings: %{"token" => token, "expected_interval_seconds" => 3600}
        })

      conn =
        post(conn, ~p"/api/heartbeat/#{token}", %{
          "status" => "healthy",
          "message" => "All systems operational"
        })

      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "accepts heartbeat with execution time", %{conn: conn} do
      token = Uptrack.Monitoring.Heartbeat.generate_token()

      _monitor =
        monitor_fixture(%{
          monitor_type: "heartbeat",
          settings: %{"token" => token, "expected_interval_seconds" => 3600}
        })

      conn =
        post(conn, ~p"/api/heartbeat/#{token}", %{
          "execution_time" => 1234
        })

      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "returns 404 for invalid token", %{conn: conn} do
      conn = post(conn, ~p"/api/heartbeat/invalid-token")

      response = json_response(conn, 404)
      assert response["ok"] == false
      assert response["error"] =~ "Invalid"
    end

    test "returns 404 for inactive monitor", %{conn: conn} do
      token = Uptrack.Monitoring.Heartbeat.generate_token()

      # Create monitor first (will be active)
      monitor =
        monitor_fixture(%{
          monitor_type: "heartbeat",
          settings: %{"token" => token, "expected_interval_seconds" => 3600}
        })

      # Update to paused status (create_changeset forces active)
      {:ok, _} = Uptrack.Monitoring.update_monitor(monitor, %{status: "paused"})

      conn = post(conn, ~p"/api/heartbeat/#{token}")

      assert json_response(conn, 404)["ok"] == false
    end
  end

  describe "HEAD /api/heartbeat/:token" do
    # Note: HEAD requests are tested via integration tests. The Phoenix test
    # framework's head/2 helper has sandbox isolation issues.
    # The route is correctly configured: HEAD /api/heartbeat/:token -> :head_ping

    test "returns 404 for invalid token on HEAD request", %{conn: conn} do
      conn = head(conn, ~p"/api/heartbeat/invalid-token")

      assert conn.status == 404
    end
  end
end
