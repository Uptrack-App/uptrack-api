defmodule UptrackWeb.Api.InvitationControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Teams
  import Uptrack.AccountsFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/organizations/:org_id/invitations" do
    test "lists pending invitations", %{conn: conn, user: user, org: org} do
      {:ok, _inv} = Teams.invite_member(org.id, "invited@example.com", "editor", user.id)

      conn = get(conn, "/api/organizations/#{org.id}/invitations")
      response = json_response(conn, 200)
      assert [invitation] = response["data"]
      assert invitation["email"] == "invited@example.com"
      assert invitation["role"] == "editor"
    end

    test "returns empty list when no invitations", %{conn: conn, org: org} do
      conn = get(conn, "/api/organizations/#{org.id}/invitations")
      response = json_response(conn, 200)
      assert response["data"] == []
    end
  end

  describe "POST /api/organizations/:org_id/invitations" do
    test "creates an invitation", %{conn: conn, org: org} do
      conn =
        post(conn, "/api/organizations/#{org.id}/invitations", %{
          email: "newmember@example.com",
          role: "editor"
        })

      response = json_response(conn, 201)
      assert response["data"]["email"] == "newmember@example.com"
    end

    test "prevents inviting existing member", %{conn: conn, user: user, org: org} do
      conn =
        post(conn, "/api/organizations/#{org.id}/invitations", %{
          email: user.email,
          role: "editor"
        })

      assert json_response(conn, 409)
    end
  end

  describe "DELETE /api/organizations/:org_id/invitations/:id" do
    test "cancels a pending invitation", %{conn: conn, user: user, org: org} do
      {:ok, inv} = Teams.invite_member(org.id, "tocancel@example.com", "viewer", user.id)

      conn = delete(conn, "/api/organizations/#{org.id}/invitations/#{inv.id}")
      assert conn.status in [200, 204]
    end
  end

  describe "GET /api/invitations/:token" do
    test "returns invitation details for a valid token", %{conn: conn, user: user, org: org} do
      {:ok, inv} = Teams.invite_member(org.id, "token@example.com", "editor", user.id)

      conn = get(conn, "/api/invitations/#{inv.token}")

      response = json_response(conn, 200)
      assert response["data"]["email"] == "token@example.com"
    end

    test "returns 404 for invalid token", %{conn: conn} do
      conn = get(conn, "/api/invitations/invalid-token-abc")
      assert json_response(conn, 404)
    end
  end

  describe "authorization" do
    test "returns 403 for wrong organization", %{conn: conn} do
      {_other_user, other_org} = user_with_org_fixture()

      conn = get(conn, "/api/organizations/#{other_org.id}/invitations")
      assert json_response(conn, 403)
    end
  end
end
