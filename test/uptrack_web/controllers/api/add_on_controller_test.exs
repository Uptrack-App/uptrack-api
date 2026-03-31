defmodule UptrackWeb.Api.AddOnControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Organizations

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/billing/add-ons" do
    test "returns 402 for free plan", %{conn: conn} do
      conn = get(conn, "/api/billing/add-ons")
      assert json_response(conn, 402)["error"]
    end

    test "returns add-ons for paid plan", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "pro"})

      conn = get(conn, "/api/billing/add-ons")
      response = json_response(conn, 200)

      assert is_list(response["data"])
      assert is_integer(response["monthly_cost_cents"])
      assert is_list(response["available_types"])
      assert length(response["available_types"]) == 5
    end
  end

  describe "POST /api/billing/add-ons" do
    test "sets add-on quantity", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "pro"})

      conn = post(conn, "/api/billing/add-ons", %{"type" => "extra_monitors", "quantity" => 10})
      response = json_response(conn, 200)

      assert response["ok"] == true
      assert response["monthly_cost_cents"] == 200  # 10 * $0.20 = $2.00 = 200 cents
    end

    test "rejects invalid type", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "pro"})

      conn = post(conn, "/api/billing/add-ons", %{"type" => "invalid", "quantity" => 5})
      assert conn.status in [422, 400]
    end

    test "rejects for free plan", %{conn: conn} do
      conn = post(conn, "/api/billing/add-ons", %{"type" => "extra_monitors", "quantity" => 5})
      assert json_response(conn, 402)["error"]
    end

    test "setting quantity to 0 removes add-on", %{conn: conn, org: org} do
      Organizations.update_organization(org, %{plan: "pro"})

      # Add then remove
      post(conn, "/api/billing/add-ons", %{"type" => "extra_monitors", "quantity" => 10})
      conn = post(conn, "/api/billing/add-ons", %{"type" => "extra_monitors", "quantity" => 0})

      response = json_response(conn, 200)
      assert response["monthly_cost_cents"] == 0
    end
  end
end
