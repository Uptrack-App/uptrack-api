defmodule UptrackWeb.Api.TeamControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.AccountsFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/organizations/:org_id/members" do
    test "lists members of the organization", %{conn: conn, user: user, org: org} do
      conn = get(conn, "/api/organizations/#{org.id}/members")
      response = json_response(conn, 200)
      assert [member] = response["data"]
      assert member["id"] == user.id
      assert member["email"] == user.email
    end

    test "returns 401 without authentication" do
      conn = build_conn()
      conn = get(conn, "/api/organizations/#{Ecto.UUID.generate()}/members")
      assert json_response(conn, 401)
    end
  end

  describe "PATCH /api/organizations/:org_id/members/:user_id" do
    test "updates a member's role", %{conn: conn, org: org} do
      member = user_fixture(%{organization_id: org.id, role: :editor})

      conn = patch(conn, "/api/organizations/#{org.id}/members/#{member.id}", %{role: "viewer"})
      response = json_response(conn, 200)
      assert response["data"]["role"] == "viewer"
    end

    test "prevents demoting the last owner", %{conn: conn, user: user, org: org} do
      conn = patch(conn, "/api/organizations/#{org.id}/members/#{user.id}", %{role: "admin"})
      assert json_response(conn, 422)
    end
  end

  describe "DELETE /api/organizations/:org_id/members/:user_id" do
    test "removes a member from the organization", %{conn: conn, org: org} do
      member = user_fixture(%{organization_id: org.id, role: :editor})

      conn = delete(conn, "/api/organizations/#{org.id}/members/#{member.id}")
      assert conn.status in [200, 204]
    end

    test "prevents removing the last owner", %{conn: conn, user: user, org: org} do
      conn = delete(conn, "/api/organizations/#{org.id}/members/#{user.id}")
      assert json_response(conn, 422)
    end
  end

  describe "POST /api/organizations/:org_id/transfer-ownership" do
    test "transfers ownership to another member", %{conn: conn, org: org} do
      new_owner = user_fixture(%{organization_id: org.id, role: :admin})

      conn =
        post(conn, "/api/organizations/#{org.id}/members/transfer-ownership", %{
          "to_user_id" => new_owner.id
        })

      response = json_response(conn, 200)
      assert response["data"]["role"] == "owner"
    end
  end

  describe "authorization" do
    test "returns 403 for wrong organization", %{conn: conn} do
      {_other_user, other_org} = user_with_org_fixture()

      conn = get(conn, "/api/organizations/#{other_org.id}/members")
      assert json_response(conn, 403)
    end
  end
end
