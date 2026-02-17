defmodule UptrackWeb.Api.ExportControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/analytics/export" do
    test "exports org-wide CSV with default date range", %{conn: conn} do
      conn = get(conn, ~p"/api/analytics/export", %{"format" => "csv"})

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ ".csv"

      body = conn.resp_body
      assert body =~ "date,monitor_name"
    end

    test "exports per-monitor CSV", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn =
        get(conn, ~p"/api/analytics/export", %{
          "format" => "csv",
          "monitor_id" => monitor.id
        })

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "date,uptime_pct,avg_response_ms"
    end

    test "respects date range parameters", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn =
        get(conn, ~p"/api/analytics/export", %{
          "format" => "csv",
          "monitor_id" => monitor.id,
          "start" => "2025-01-01",
          "end" => "2025-01-07"
        })

      assert conn.status == 200
      body = conn.resp_body
      # Per-monitor CSV includes date rows for each day in range
      assert body =~ "date,uptime_pct"
      assert body =~ "2025-01-01"
      assert body =~ "2025-01-07"
    end

    test "returns 404 for nonexistent monitor", %{conn: conn} do
      conn =
        get(conn, ~p"/api/analytics/export", %{
          "format" => "csv",
          "monitor_id" => Uniq.UUID.uuid7()
        })

      assert json_response(conn, 404)
    end

    test "returns 404 for monitor in different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn =
        get(conn, ~p"/api/analytics/export", %{
          "format" => "csv",
          "monitor_id" => other_monitor.id
        })

      assert json_response(conn, 404)
    end

    test "returns 401 without authentication" do
      conn =
        build_conn()
        |> get(~p"/api/analytics/export", %{"format" => "csv"})

      assert json_response(conn, 401)
    end
  end
end
