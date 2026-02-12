defmodule UptrackWeb.Api.AuditLogControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Teams

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/organizations/:org_id/audit-logs" do
    test "returns audit logs for the organization", %{conn: conn, user: user, org: org} do
      Teams.log_action(org.id, user.id, "monitor.created", "monitor", Ecto.UUID.generate())

      conn = get(conn, "/api/organizations/#{org.id}/audit-logs")
      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) >= 1
    end

    test "supports limit parameter", %{conn: conn, user: user, org: org} do
      for _ <- 1..5 do
        Teams.log_action(org.id, user.id, "monitor.created", "monitor", Ecto.UUID.generate())
      end

      conn = get(conn, "/api/organizations/#{org.id}/audit-logs?limit=2")
      response = json_response(conn, 200)
      assert length(response["data"]) <= 2
    end

    test "includes user information in logs", %{conn: conn, user: user, org: org} do
      Teams.log_action(org.id, user.id, "user.logged_in", "user", user.id)

      conn = get(conn, "/api/organizations/#{org.id}/audit-logs")
      response = json_response(conn, 200)
      log = hd(response["data"])
      assert log["user"]["id"] == user.id
      assert log["user"]["email"] == user.email
    end

    test "returns 401 without authentication" do
      conn = build_conn()
      conn = get(conn, "/api/organizations/#{Ecto.UUID.generate()}/audit-logs")
      assert json_response(conn, 401)
    end
  end
end
