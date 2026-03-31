defmodule UptrackWeb.Plugs.ApiAuthTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "session-based auth" do
    test "authenticated session can access protected endpoint" do
      {user, _org} = user_with_org_fixture()

      conn =
        build_conn()
        |> init_test_session(%{user_id: user.id})
        |> get("/api/auth/me")

      assert json_response(conn, 200)["user"]["id"] == user.id
    end

    test "no session returns 401" do
      conn = build_conn() |> get("/api/auth/me")
      assert conn.status in [401, 302]
    end
  end

  describe "bearer token auth" do
    test "valid API key authenticates" do
      {user, org} = user_with_org_fixture()
      {:ok, api_key} = Uptrack.Accounts.ApiKeys.create_api_key(%{
        name: "test-key",
        organization_id: org.id,
        created_by_id: user.id
      })

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{api_key.raw_key}")
        |> get("/api/auth/me")

      assert json_response(conn, 200)["user"]["id"] == user.id
    end

    test "invalid API key returns 401" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer utk_completely_invalid_key")
        |> get("/api/auth/me")

      assert conn.status in [401, 302]
    end

    test "empty bearer token returns 401" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer ")
        |> get("/api/auth/me")

      assert conn.status in [401, 302]
    end
  end
end
