defmodule Uptrack.BillingTest do
  use Uptrack.DataCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Billing
  alias Uptrack.Billing.Subscription
  alias Uptrack.Organizations

  @moduletag :capture_log

  setup do
    Application.put_env(:uptrack, :paddle, [
      api_key: "test_api_key",
      webhook_secret: "test_secret",
      base_url: "https://sandbox-api.paddle.com",
      checkout_url: "https://sandbox-checkout.paddle.com",
      price_id_pro: "pri_pro_test",
      price_id_team: "pri_team_test"
    ])

    :ok
  end

  describe "plan_limits/1" do
    test "returns correct limits for free plan" do
      limits = Billing.plan_limits("free")
      assert limits.monitors == 10
      assert limits.alert_channels == 2
      assert limits.status_pages == 1
      assert limits.team_members == 1
      assert limits.min_interval == 180
    end

    test "returns correct limits for pro plan" do
      limits = Billing.plan_limits("pro")
      assert limits.monitors == 25
      assert limits.alert_channels == :unlimited
      assert limits.status_pages == 3
      assert limits.team_members == 5
      assert limits.min_interval == 30
    end

    test "returns correct limits for team plan" do
      limits = Billing.plan_limits("team")
      assert limits.monitors == 150
      assert limits.alert_channels == :unlimited
      assert limits.status_pages == :unlimited
      assert limits.team_members == :unlimited
      assert limits.min_interval == 30
    end

    test "returns free limits for unknown plan" do
      assert Billing.plan_limits("unknown") == Billing.plan_limits("free")
    end
  end

  describe "check_plan_limit/2" do
    test "allows creation when under limit", %{} do
      org = organization_fixture()
      assert :ok = Billing.check_plan_limit(org, :monitors)
    end

    test "rejects creation when at monitor limit", %{} do
      {user, org} = user_with_org_fixture()

      # Free plan allows 10 monitors — create exactly 10
      for _ <- 1..10 do
        monitor_fixture(organization_id: org.id, user_id: user.id)
      end

      assert {:error, msg} = Billing.check_plan_limit(org, :monitors)
      assert msg =~ "monitor"
      assert msg =~ "10"
      assert msg =~ "Upgrade"
    end

    test "allows unlimited alert channels on pro plan", %{} do
      org = organization_fixture(plan: "pro")
      assert :ok = Billing.check_plan_limit(org, :alert_channels)
    end

    test "rejects when at free plan alert channel limit", %{} do
      {user, org} = user_with_org_fixture()

      # Free plan allows 2 alert channels
      alert_channel_fixture(organization_id: org.id, user_id: user.id)
      alert_channel_fixture(organization_id: org.id, user_id: user.id)

      assert {:error, msg} = Billing.check_plan_limit(org, :alert_channels)
      assert msg =~ "alert channel"
      assert msg =~ "2"
    end
  end

  describe "check_interval_limit/2" do
    test "allows valid interval for free plan" do
      org = organization_fixture()
      assert :ok = Billing.check_interval_limit(org, 300)
      assert :ok = Billing.check_interval_limit(org, 180)
    end

    test "rejects too-fast interval for free plan" do
      org = organization_fixture()
      assert {:error, msg} = Billing.check_interval_limit(org, 60)
      assert msg =~ "180 seconds"
    end

    test "allows 30-second interval for pro plan" do
      org = organization_fixture(plan: "pro")
      assert :ok = Billing.check_interval_limit(org, 30)
    end

    test "rejects sub-30s interval for pro plan" do
      org = organization_fixture(plan: "pro")
      assert {:error, _} = Billing.check_interval_limit(org, 15)
    end
  end

  describe "subscription queries" do
    test "get_active_subscription returns active subscription" do
      org = organization_fixture()
      {:ok, sub} = insert_subscription(org, "pro", "active")

      result = Billing.get_active_subscription(org.id)
      assert result.id == sub.id
      assert result.plan == "pro"
    end

    test "get_active_subscription returns nil for cancelled subscription" do
      org = organization_fixture()
      insert_subscription(org, "pro", "cancelled")

      assert Billing.get_active_subscription(org.id) == nil
    end

    test "get_active_subscription returns nil when no subscription" do
      org = organization_fixture()
      assert Billing.get_active_subscription(org.id) == nil
    end

    test "get_subscription_by_paddle_id finds by paddle ID" do
      org = organization_fixture()
      {:ok, sub} = insert_subscription(org, "team", "active")

      result = Billing.get_subscription_by_paddle_id(sub.paddle_subscription_id)
      assert result.id == sub.id
    end
  end

  describe "webhook handlers" do
    test "handle_webhook_event subscription.activated creates subscription" do
      org = organization_fixture()

      data = %{
        "id" => "sub_new_123",
        "customer_id" => "ctm_new_123",
        "custom_data" => %{"organization_id" => org.id, "plan" => "pro"},
        "items" => [%{"price" => %{"id" => "pri_pro_test"}}],
        "current_billing_period" => %{
          "starts_at" => "2026-02-16T00:00:00Z",
          "ends_at" => "2026-03-16T00:00:00Z"
        }
      }

      assert {:ok, sub} = Billing.handle_webhook_event("subscription.activated", data)
      assert sub.paddle_subscription_id == "sub_new_123"
      assert sub.plan == "pro"
      assert sub.status == "active"

      # Org plan updated
      updated_org = Organizations.get_organization(org.id)
      assert updated_org.plan == "pro"
    end

    test "handle_webhook_event subscription.activated updates existing subscription" do
      org = organization_fixture()
      {:ok, existing} = insert_subscription(org, "pro", "active", paddle_sub_id: "sub_existing")

      data = %{
        "id" => "sub_existing",
        "customer_id" => "ctm_123",
        "custom_data" => %{"organization_id" => org.id, "plan" => "team"},
        "items" => [%{"price" => %{"id" => "pri_team_test"}}],
        "current_billing_period" => %{
          "starts_at" => "2026-03-01T00:00:00Z",
          "ends_at" => "2026-04-01T00:00:00Z"
        }
      }

      assert {:ok, updated} = Billing.handle_webhook_event("subscription.activated", data)
      assert updated.id == existing.id
      assert updated.plan == "team"
    end

    test "handle_webhook_event subscription.canceled downgrades to free" do
      org = organization_fixture(plan: "pro")
      {:ok, sub} = insert_subscription(org, "pro", "active")

      data = %{"id" => sub.paddle_subscription_id}

      Billing.handle_webhook_event("subscription.canceled", data)

      updated_sub = Billing.get_subscription_by_paddle_id(sub.paddle_subscription_id)
      assert updated_sub.status == "cancelled"

      updated_org = Organizations.get_organization(org.id)
      assert updated_org.plan == "free"
    end

    test "handle_webhook_event subscription.past_due marks subscription" do
      org = organization_fixture()
      {:ok, sub} = insert_subscription(org, "pro", "active")

      data = %{"id" => sub.paddle_subscription_id}

      Billing.handle_webhook_event("subscription.past_due", data)

      updated_sub = Billing.get_subscription_by_paddle_id(sub.paddle_subscription_id)
      assert updated_sub.status == "past_due"
    end

    test "handle_webhook_event ignores unknown events" do
      assert :ok = Billing.handle_webhook_event("customer.updated", %{})
    end
  end

  # --- Helpers ---

  defp insert_subscription(org, plan, status, opts \\ []) do
    paddle_sub_id = opts[:paddle_sub_id] || "sub_#{System.unique_integer([:positive])}"

    %Subscription{}
    |> Subscription.changeset(%{
      organization_id: org.id,
      paddle_subscription_id: paddle_sub_id,
      paddle_customer_id: "ctm_#{System.unique_integer([:positive])}",
      plan: plan,
      status: status,
      current_period_start: DateTime.utc_now() |> DateTime.truncate(:second),
      current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
    })
    |> Uptrack.AppRepo.insert()
  end
end
