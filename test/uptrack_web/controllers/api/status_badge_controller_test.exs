defmodule UptrackWeb.Api.StatusBadgeControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "GET /api/badge/:slug" do
    test "returns SVG badge for valid status page", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "svg"
      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/badge/non-existent")

      assert conn.status == 404
      # Even 404 returns SVG with error message
      assert conn.resp_body =~ "<svg"
    end

    test "supports flat style (default)", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "supports flat-square style", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}?style=flat-square")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "supports for-the-badge style", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}?style=for-the-badge")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "supports custom label", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}?label=My+Service")

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "My Service"
    end

    test "sets proper cache headers", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}")

      cache_control = get_resp_header(conn, "cache-control")
      assert cache_control != []
      assert List.first(cache_control) =~ "max-age"
    end
  end

  describe "GET /api/badge/:slug/uptime" do
    test "returns uptime badge", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}/uptime")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "supports days parameter", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}/uptime?days=7")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
      assert conn.resp_body =~ "7d"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/badge/non-existent/uptime")

      assert conn.status == 404
    end
  end

  describe "GET /api/badge/:slug/status" do
    test "returns status badge", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/badge/#{status_page.slug}/status")

      assert conn.status == 200
      assert conn.resp_body =~ "<svg"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/badge/non-existent/status")

      assert conn.status == 404
    end
  end
end
