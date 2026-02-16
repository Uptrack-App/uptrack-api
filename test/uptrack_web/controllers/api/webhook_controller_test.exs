defmodule UptrackWeb.Api.WebhookControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Billing
  alias Uptrack.Organizations

  @moduletag :capture_log

  @webhook_secret "test_webhook_secret_key"

  setup do
    Application.put_env(:uptrack, :paddle, [
      api_key: "test_api_key",
      webhook_secret: @webhook_secret,
      base_url: "https://sandbox-api.paddle.com",
      checkout_url: "https://sandbox-checkout.paddle.com",
      price_id_pro: "pri_pro_test",
      price_id_team: "pri_team_test"
    ])

    :ok
  end

  describe "POST /api/webhooks/paddle" do
    test "processes subscription.activated event", %{conn: conn} do
      org = organization_fixture()

      payload = subscription_event_payload("subscription.activated", %{
        "custom_data" => %{"organization_id" => org.id, "plan" => "pro"},
        "items" => [%{"price" => %{"id" => "pri_pro_test"}}]
      })

      conn = post_webhook(conn, payload)

      assert json_response(conn, 200)["received"] == true

      # Verify subscription was created
      sub = Billing.get_active_subscription(org.id)
      assert sub != nil
      assert sub.plan == "pro"
      assert sub.status == "active"

      # Verify org plan was updated
      updated_org = Organizations.get_organization(org.id)
      assert updated_org.plan == "pro"
    end

    test "processes subscription.created event", %{conn: conn} do
      org = organization_fixture()

      payload = subscription_event_payload("subscription.created", %{
        "custom_data" => %{"organization_id" => org.id, "plan" => "team"},
        "items" => [%{"price" => %{"id" => "pri_team_test"}}]
      })

      conn = post_webhook(conn, payload)

      assert json_response(conn, 200)["received"] == true

      sub = Billing.get_active_subscription(org.id)
      assert sub.plan == "team"
    end

    test "processes subscription.canceled event", %{conn: conn} do
      org = organization_fixture()

      # First create a subscription
      {:ok, sub} = create_test_subscription(org, "pro")
      assert sub.status == "active"

      payload = Jason.encode!(%{
        "event_type" => "subscription.canceled",
        "data" => %{
          "id" => sub.paddle_subscription_id,
          "customer_id" => "ctm_test_123",
          "status" => "canceled"
        }
      })

      conn = post_webhook(conn, payload)

      assert json_response(conn, 200)["received"] == true

      # Verify subscription was cancelled
      updated_sub = Billing.get_subscription_by_paddle_id(sub.paddle_subscription_id)
      assert updated_sub.status == "cancelled"
      assert updated_sub.cancelled_at != nil

      # Verify org downgraded to free
      updated_org = Organizations.get_organization(org.id)
      assert updated_org.plan == "free"
    end

    test "processes subscription.past_due event", %{conn: conn} do
      org = organization_fixture()
      {:ok, sub} = create_test_subscription(org, "pro")

      payload = Jason.encode!(%{
        "event_type" => "subscription.past_due",
        "data" => %{"id" => sub.paddle_subscription_id}
      })

      conn = post_webhook(conn, payload)

      assert json_response(conn, 200)["received"] == true

      updated_sub = Billing.get_subscription_by_paddle_id(sub.paddle_subscription_id)
      assert updated_sub.status == "past_due"
    end

    test "rejects request with missing signature", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_private(:raw_body, "{}")
        |> post(~p"/api/webhooks/paddle", %{})

      assert json_response(conn, 401)["error"] == "Missing signature"
    end

    test "rejects request with invalid signature", %{conn: conn} do
      body = Jason.encode!(%{"event_type" => "test", "data" => %{}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("paddle-signature", "ts=123;h1=invalid_hash")
        |> put_private(:raw_body, body)
        |> post(~p"/api/webhooks/paddle", Jason.decode!(body))

      assert json_response(conn, 401)["error"] == "Invalid signature"
    end

    test "ignores unknown event types gracefully", %{conn: conn} do
      payload = Jason.encode!(%{
        "event_type" => "customer.updated",
        "data" => %{"id" => "ctm_test"}
      })

      conn = post_webhook(conn, payload)

      assert json_response(conn, 200)["received"] == true
    end
  end

  # --- Helpers ---

  defp post_webhook(conn, raw_body) do
    ts = "#{System.system_time(:second)}"
    signed_payload = "#{ts}:#{raw_body}"

    h1 =
      :crypto.mac(:hmac, :sha256, @webhook_secret, signed_payload)
      |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("paddle-signature", "ts=#{ts};h1=#{h1}")
    |> put_private(:raw_body, raw_body)
    |> post(~p"/api/webhooks/paddle", Jason.decode!(raw_body))
  end

  defp subscription_event_payload(event_type, overrides) do
    data =
      %{
        "id" => "sub_test_#{System.unique_integer([:positive])}",
        "customer_id" => "ctm_test_#{System.unique_integer([:positive])}",
        "status" => "active",
        "current_billing_period" => %{
          "starts_at" => "2026-02-16T00:00:00Z",
          "ends_at" => "2026-03-16T00:00:00Z"
        }
      }
      |> Map.merge(overrides)

    Jason.encode!(%{"event_type" => event_type, "data" => data})
  end

  defp create_test_subscription(org, plan) do
    alias Uptrack.Billing.Subscription

    %Subscription{}
    |> Subscription.changeset(%{
      organization_id: org.id,
      paddle_subscription_id: "sub_test_#{System.unique_integer([:positive])}",
      paddle_customer_id: "ctm_test_#{System.unique_integer([:positive])}",
      plan: plan,
      status: "active",
      current_period_start: DateTime.utc_now() |> DateTime.truncate(:second),
      current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
    })
    |> Uptrack.AppRepo.insert()
  end
end
