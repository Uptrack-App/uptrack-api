defmodule UptrackWeb.Plugs.RequireAdminTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "RequireAdmin plug" do
    test "allows request when user is_admin = true" do
      {user, _org} = user_with_org_fixture()
      {:ok, admin} = Uptrack.AppRepo.update(Ecto.Changeset.change(user, is_admin: true))

      conn =
        build_conn()
        |> init_test_session(%{user_id: admin.id})
        |> get("/api/admin/users")

      assert conn.status != 403
    end

    test "returns 403 when user is_admin = false" do
      {user, _org} = user_with_org_fixture()

      conn =
        build_conn()
        |> init_test_session(%{user_id: user.id})
        |> get("/api/admin/users")

      assert json_response(conn, 403)["error"]["message"] == "forbidden"
    end

    test "returns 403 when no user assigned" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> UptrackWeb.Plugs.RequireAdmin.call([])

      assert conn.status == 403
      assert conn.halted
    end
  end
end
