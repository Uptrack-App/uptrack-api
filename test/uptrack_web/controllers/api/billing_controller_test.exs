defmodule UptrackWeb.Api.BillingControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Billing.Subscription
  alias Uptrack.AppRepo

  setup %{conn: conn} do
    # Store original config and set mock
    original = Application.get_env(:uptrack, :paddle_client)
    Application.put_env(:uptrack, :paddle_client, Uptrack.Billing.PaddleClientMock)

    # Ensure paddle config is set for tests
    Application.put_env(:uptrack, :paddle, [
      api_key: "test_api_key",
      webhook_secret: "test_secret",
      base_url: "https://sandbox-api.paddle.com",
      checkout_url: "https://sandbox-checkout.paddle.com",
      price_id_pro: "pri_pro_test",
      price_id_team: "pri_team_test"
    ])

    %{conn: conn, user: user, org: org} = setup_api_auth(conn)

    on_exit(fn ->
      if original, do: Application.put_env(:uptrack, :paddle_client, original),
      else: Application.delete_env(:uptrack, :paddle_client)
    end)

    {:ok, conn: conn, user: user, org: org}
  end

  describe "POST /api/billing/checkout" do
    test "creates checkout session for pro plan", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/checkout", %{"plan" => "pro"})
      assert %{"checkout_url" => url, "transaction_id" => _txn_id} = json_response(conn, 200)
      assert url =~ "paddle.com"
    end

    test "creates checkout session for team plan", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/checkout", %{"plan" => "team"})
      assert %{"checkout_url" => _, "transaction_id" => _} = json_response(conn, 200)
    end

    test "rejects invalid plan", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/checkout", %{"plan" => "enterprise"})
      assert %{"error" => %{"message" => msg}} = json_response(conn, 400)
      assert msg =~ "Invalid plan"
    end

    test "returns error when paddle client fails", %{conn: conn} do
      Process.put(:paddle_create_transaction, {:error, "API rate limited"})
      conn = post(conn, ~p"/api/billing/checkout", %{"plan" => "pro"})
      assert json_response(conn, 422)["error"]
    end
  end

  describe "GET /api/billing/subscription" do
    test "returns null when no subscription", %{conn: conn, org: org} do
      conn = get(conn, ~p"/api/billing/subscription")
      assert %{"data" => nil, "plan" => plan} = json_response(conn, 200)
      assert plan == org.plan
    end

    test "returns active subscription", %{conn: conn, org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          paddle_subscription_id: "sub_test_#{System.unique_integer([:positive])}",
          paddle_customer_id: "ctm_test_#{System.unique_integer([:positive])}",
          plan: "pro",
          status: "active",
          current_period_start: now,
          current_period_end: DateTime.add(now, 30 * 86400, :second)
        })
        |> AppRepo.insert()

      conn = get(conn, ~p"/api/billing/subscription")
      assert %{"data" => data, "plan" => _} = json_response(conn, 200)
      assert data["plan"] == "pro"
      assert data["status"] == "active"
    end
  end

  describe "POST /api/billing/cancel" do
    test "cancels active subscription", %{conn: conn, org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          paddle_subscription_id: "sub_cancel_#{System.unique_integer([:positive])}",
          paddle_customer_id: "ctm_cancel_#{System.unique_integer([:positive])}",
          plan: "pro",
          status: "active",
          current_period_start: now,
          current_period_end: DateTime.add(now, 30 * 86400, :second)
        })
        |> AppRepo.insert()

      conn = post(conn, ~p"/api/billing/cancel")
      assert %{"ok" => true} = json_response(conn, 200)
    end

    test "returns 404 when no subscription", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/cancel")
      assert %{"error" => %{"message" => _}} = json_response(conn, 404)
    end
  end

  describe "POST /api/billing/change-plan" do
    test "returns 422 when no active subscription", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/change-plan", %{"plan" => "team"})
      assert %{"error" => %{"message" => _}} = json_response(conn, 422)
    end

    test "rejects invalid plan", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/change-plan", %{"plan" => "invalid"})
      assert %{"error" => %{"message" => _}} = json_response(conn, 400)
    end
  end

  describe "POST /api/billing/portal" do
    test "returns 404 when no subscription", %{conn: conn} do
      conn = post(conn, ~p"/api/billing/portal")
      assert %{"error" => _} = json_response(conn, 404)
    end

    test "returns portal URL with active subscription", %{conn: conn, org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _sub} =
        %Subscription{}
        |> Subscription.changeset(%{
          organization_id: org.id,
          paddle_subscription_id: "sub_portal_#{System.unique_integer([:positive])}",
          paddle_customer_id: "ctm_portal_#{System.unique_integer([:positive])}",
          plan: "pro",
          status: "active",
          current_period_start: now,
          current_period_end: DateTime.add(now, 30 * 86400, :second)
        })
        |> AppRepo.insert()

      conn = post(conn, ~p"/api/billing/portal")
      assert %{"portal_url" => url} = json_response(conn, 200)
      assert url =~ "paddle.com"
    end
  end

  describe "authentication" do
    test "returns 401 for unauthenticated request", %{} do
      conn = build_conn()
      conn = get(conn, ~p"/api/billing/subscription")
      assert conn.status in [401, 302]
    end
  end
end
