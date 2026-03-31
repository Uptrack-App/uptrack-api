defmodule UptrackWeb.Api.CustomSenderControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Organizations

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/custom-sender" do
    test "returns null when no sender configured", %{conn: conn} do
      conn = get(conn, "/api/custom-sender")
      assert json_response(conn, 200)["data"] == nil
    end
  end

  describe "POST /api/custom-sender" do
    test "rejects on free plan", %{conn: conn} do
      conn = post(conn, "/api/custom-sender", %{
        "sender_name" => "My Company",
        "sender_email" => "alerts@mycompany.com"
      })

      assert json_response(conn, 402)["error"]["message"] =~ "Business"
    end

    test "creates sender on business plan", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "business"})

      conn = post(conn, "/api/custom-sender", %{
        "sender_name" => "My Company",
        "sender_email" => "alerts@mycompany.com"
      })

      assert json_response(conn, 200)["ok"] == true

      show_conn = get(conn, "/api/custom-sender")
      data = json_response(show_conn, 200)["data"]
      assert data["sender_name"] == "My Company"
      assert data["sender_email"] == "alerts@mycompany.com"
      assert data["verified"] == false
    end
  end

  describe "DELETE /api/custom-sender" do
    test "removes sender", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "business"})

      post(conn, "/api/custom-sender", %{
        "sender_name" => "Del",
        "sender_email" => "del@test.com"
      })

      conn = delete(conn, "/api/custom-sender")
      assert json_response(conn, 200)["ok"] == true

      show_conn = get(conn, "/api/custom-sender")
      assert json_response(show_conn, 200)["data"] == nil
    end
  end
end
