defmodule UptrackWeb.Api.DomainControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/status-pages/:status_page_id/domain" do
    test "returns domain config for status page", %{conn: conn, user: user, org: org} do
      status_page =
        status_page_fixture(%{
          user_id: user.id,
          organization_id: org.id,
          custom_domain: "status.example.com"
        })

      conn = get(conn, ~p"/api/status-pages/#{status_page.id}/domain")
      response = json_response(conn, 200)

      assert response["custom_domain"] == "status.example.com"
      assert response["domain_verified"] == false
      assert is_binary(response["domain_verification_token"])
      assert is_map(response["dns_records"])
    end

    test "returns null dns_records when no custom domain", %{conn: conn, user: user, org: org} do
      status_page = status_page_fixture(%{user_id: user.id, organization_id: org.id})

      conn = get(conn, ~p"/api/status-pages/#{status_page.id}/domain")
      response = json_response(conn, 200)

      assert is_nil(response["custom_domain"])
      assert is_nil(response["dns_records"])
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = get(conn, ~p"/api/status-pages/00000000-0000-0000-0000-000000000000/domain")
      response = json_response(conn, 404)

      assert response["error"] =~ "not found"
    end
  end

  describe "PUT /api/status-pages/:status_page_id/domain" do
    test "sets a custom domain", %{conn: conn, user: user, org: org} do
      status_page = status_page_fixture(%{user_id: user.id, organization_id: org.id})

      conn =
        put(conn, ~p"/api/status-pages/#{status_page.id}/domain", %{
          "custom_domain" => "status.myapp.com"
        })

      response = json_response(conn, 200)

      assert response["custom_domain"] == "status.myapp.com"
      assert response["domain_verified"] == false
      assert is_binary(response["domain_verification_token"])
      assert is_map(response["dns_records"])
    end

    test "updates an existing custom domain", %{conn: conn, user: user, org: org} do
      status_page =
        status_page_fixture(%{
          user_id: user.id,
          organization_id: org.id,
          custom_domain: "old.example.com"
        })

      conn =
        put(conn, ~p"/api/status-pages/#{status_page.id}/domain", %{
          "custom_domain" => "new.example.com"
        })

      response = json_response(conn, 200)
      assert response["custom_domain"] == "new.example.com"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn =
        put(conn, ~p"/api/status-pages/00000000-0000-0000-0000-000000000000/domain", %{
          "custom_domain" => "test.example.com"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/status-pages/:status_page_id/domain/verify" do
    test "returns error when no custom domain configured", %{conn: conn, user: user, org: org} do
      status_page = status_page_fixture(%{user_id: user.id, organization_id: org.id})

      conn = post(conn, ~p"/api/status-pages/#{status_page.id}/domain/verify")
      response = json_response(conn, 422)

      assert response["error"] =~ "No custom domain"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = post(conn, ~p"/api/status-pages/00000000-0000-0000-0000-000000000000/domain/verify")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "DELETE /api/status-pages/:status_page_id/domain" do
    test "removes custom domain", %{conn: conn, user: user, org: org} do
      status_page =
        status_page_fixture(%{
          user_id: user.id,
          organization_id: org.id,
          custom_domain: "remove-me.example.com"
        })

      conn = delete(conn, ~p"/api/status-pages/#{status_page.id}/domain")
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["message"] =~ "removed"
    end

    test "returns 404 for non-existent status page", %{conn: conn} do
      conn = delete(conn, ~p"/api/status-pages/00000000-0000-0000-0000-000000000000/domain")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "authentication" do
    test "returns 401 for unauthenticated requests", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()

      conn = get(conn, ~p"/api/status-pages/1/domain")
      assert json_response(conn, 401)
    end
  end
end
