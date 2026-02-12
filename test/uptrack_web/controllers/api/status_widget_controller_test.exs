defmodule UptrackWeb.Api.StatusWidgetControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "GET /api/widget/:slug/script.js" do
    test "returns JavaScript widget code", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/script.js")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "javascript"
      assert conn.status == 200
      body = conn.resp_body
      # Check for widget-related JavaScript content
      assert body =~ "uptrack" or body =~ "widget" or body =~ "function"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/widget/non-existent/script.js")

      assert conn.status == 404
      assert conn.resp_body =~ "not found"
    end

    test "supports theme parameter", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/script.js?theme=dark")

      assert conn.status == 200
      assert conn.resp_body =~ "dark"
    end

    test "sets cache headers", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/script.js")

      cache_control = get_resp_header(conn, "cache-control")
      assert cache_control != []
    end
  end

  describe "GET /api/widget/:slug/data" do
    test "returns JSON status data", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/data")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "json"
      data = json_response(conn, 200)
      assert data["slug"] == status_page.slug
      assert data["name"] == status_page.name
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/widget/non-existent/data")

      response = json_response(conn, 404)
      assert response["error"] != nil
    end

    test "includes status information", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/data")

      data = json_response(conn, 200)
      assert data["status"] != nil
      assert data["status_text"] != nil
      assert data["status_color"] != nil
    end

    test "includes uptime information", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/data")

      data = json_response(conn, 200)
      assert data["uptime"] != nil
      assert data["uptime_text"] != nil
    end

    test "sets cache headers", %{conn: conn} do
      status_page = status_page_fixture()

      conn = get(conn, ~p"/api/widget/#{status_page.slug}/data")

      cache_control = get_resp_header(conn, "cache-control")
      assert cache_control != []
    end
  end
end
