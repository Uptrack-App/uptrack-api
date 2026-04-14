defmodule UptrackWeb.Plugs.ImpersonationTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias UptrackWeb.Plugs.Impersonation

  describe "no impersonation state" do
    test "passes through without modification" do
      {user, org} = user_with_org_fixture()

      conn =
        build_conn()
        |> init_test_session(%{})
        |> assign(:auth_method, :session)
        |> assign(:current_user, user)
        |> assign(:current_organization, org)
        |> Impersonation.call([])

      assert conn.assigns.current_user.id == user.id
      refute Map.has_key?(conn.assigns, :impersonating_admin)
    end
  end

  describe "API key auth" do
    test "does not activate even with session keys present" do
      {admin, admin_org} = user_with_org_fixture()
      {target, _} = user_with_org_fixture()

      conn =
        build_conn()
        |> init_test_session(%{})
        |> assign(:auth_method, :api_key)
        |> assign(:current_user, admin)
        |> assign(:current_organization, admin_org)
        |> put_session(:impersonating_user_id, target.id)
        |> put_session(:impersonation_started_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Impersonation.call([])

      assert conn.assigns.current_user.id == admin.id
      refute Map.has_key?(conn.assigns, :impersonating_admin)
    end
  end

  describe "active impersonation" do
    test "swaps current_user to target and sets impersonating_admin" do
      {admin, admin_org} = user_with_org_fixture()
      {target, target_org} = user_with_org_fixture()

      conn =
        build_conn()
        |> init_test_session(%{})
        |> assign(:auth_method, :session)
        |> assign(:current_user, admin)
        |> assign(:current_organization, admin_org)
        |> put_session(:impersonating_user_id, target.id)
        |> put_session(:impersonation_started_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Impersonation.call([])

      assert conn.assigns.current_user.id == target.id
      assert conn.assigns.impersonating_admin.id == admin.id
      assert conn.assigns.current_organization.id == target_org.id
    end
  end

  describe "expired impersonation" do
    test "returns 403 impersonation_expired and clears session" do
      {admin, admin_org} = user_with_org_fixture()
      {target, _} = user_with_org_fixture()

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3601, :second)
        |> DateTime.to_iso8601()

      conn =
        build_conn()
        |> init_test_session(%{})
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> assign(:auth_method, :session)
        |> assign(:current_user, admin)
        |> assign(:current_organization, admin_org)
        |> put_session(:impersonating_user_id, target.id)
        |> put_session(:impersonation_started_at, expired_at)
        |> Impersonation.call([])

      assert conn.status == 403
      assert conn.halted
      assert json_response(conn, 403)["error"]["message"] == "impersonation_expired"
      assert get_session(conn, :impersonating_user_id) == nil
    end
  end

  describe "deleted target user" do
    test "clears session and continues as admin" do
      {admin, admin_org} = user_with_org_fixture()
      deleted_user_id = Uniq.UUID.uuid7()

      conn =
        build_conn()
        |> init_test_session(%{})
        |> assign(:auth_method, :session)
        |> assign(:current_user, admin)
        |> assign(:current_organization, admin_org)
        |> put_session(:impersonating_user_id, deleted_user_id)
        |> put_session(:impersonation_started_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Impersonation.call([])

      assert conn.assigns.current_user.id == admin.id
      assert get_session(conn, :impersonating_user_id) == nil
      refute conn.halted
    end
  end
end
