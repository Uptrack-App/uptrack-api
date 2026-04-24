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
      price_id_pro_annual: "pri_pro_annual_test",
      price_id_team: "pri_team_test",
      price_id_team_annual: "pri_team_annual_test",
      price_id_business: "pri_business_test",
      price_id_business_annual: "pri_business_annual_test"
    ])

    :ok
  end

  describe "plan_limits/1" do
    test "returns correct limits for free plan" do
      limits = Billing.plan_limits("free")
      assert limits.monitors == 50
      assert limits.alert_channels == 3
      assert limits.status_pages == 5
      assert limits.team_members == 2
      assert limits.min_interval == 30
      assert limits.fast_monitors == 10
      assert limits.quick_monitors == :unlimited
      assert limits.retention_days == 90
    end

    test "returns correct limits for pro plan" do
      limits = Billing.plan_limits("pro")
      assert limits.monitors == 30
      assert limits.alert_channels == 5
      assert limits.status_pages == 5
      assert limits.team_members == 3
      assert limits.min_interval == 30
      assert limits.fast_monitors == :unlimited
      assert limits.retention_days == 730
    end

    test "returns correct limits for team plan" do
      limits = Billing.plan_limits("team")
      assert limits.monitors == 60
      assert limits.alert_channels == :unlimited
      assert limits.status_pages == :unlimited
      assert limits.team_members == 5
      assert limits.min_interval == 30
      assert limits.fast_monitors == :unlimited
      assert limits.retention_days == 730
    end

    test "returns correct limits for business plan" do
      limits = Billing.plan_limits("business")
      assert limits.monitors == 625
      assert limits.alert_channels == :unlimited
      assert limits.status_pages == :unlimited
      assert limits.team_members == 15
      assert limits.min_interval == 30
      assert limits.fast_monitors == :unlimited
      assert limits.retention_days == 1825
      assert limits.subscribers == 10_000
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

      # Free plan allows 50 monitors — create exactly 50
      for _ <- 1..50 do
        monitor_fixture(organization_id: org.id, user_id: user.id)
      end

      assert {:error, msg} = Billing.check_plan_limit(org, :monitors)
      assert msg =~ "monitor"
      assert msg =~ "50"
      assert msg =~ "Upgrade"
    end

    test "allows unlimited alert channels on pro plan", %{} do
      org = organization_fixture(plan: "pro")
      assert :ok = Billing.check_plan_limit(org, :alert_channels)
    end

    test "rejects when at free plan alert channel limit", %{} do
      {user, org} = user_with_org_fixture()

      # Free plan allows 3 alert channels
      alert_channel_fixture(organization_id: org.id, user_id: user.id)
      alert_channel_fixture(organization_id: org.id, user_id: user.id)
      alert_channel_fixture(organization_id: org.id, user_id: user.id)

      assert {:error, msg} = Billing.check_plan_limit(org, :alert_channels)
      assert msg =~ "alert channel"
      assert msg =~ "3"
    end
  end

  describe "check_interval_limit/2" do
    test "allows 30s interval for free plan" do
      org = organization_fixture()
      assert :ok = Billing.check_interval_limit(org, 30)
      assert :ok = Billing.check_interval_limit(org, 60)
      assert :ok = Billing.check_interval_limit(org, 180)
    end

    test "allows 30s on all paid plans" do
      for plan <- ["pro", "team", "business"] do
        org = organization_fixture(plan: plan)
        assert :ok = Billing.check_interval_limit(org, 30)
      end
    end

    test "rejects sub-30s interval" do
      org = organization_fixture()
      assert {:error, msg} = Billing.check_interval_limit(org, 15)
      assert msg =~ "30 seconds"
    end
  end

  describe "can_use_feature?/2" do
    test "business-only features require business plan" do
      free_org = organization_fixture()
      pro_org = organization_fixture(plan: "pro")
      team_org = organization_fixture(plan: "team")
      biz_org = organization_fixture(plan: "business")

      for feature <- [:whitelabel, :sso, :rbac, :custom_email_sender] do
        refute Billing.can_use_feature?(free_org, feature)
        refute Billing.can_use_feature?(pro_org, feature)
        refute Billing.can_use_feature?(team_org, feature)
        assert Billing.can_use_feature?(biz_org, feature)
      end
    end

    test "team features require team or business plan" do
      free_org = organization_fixture()
      pro_org = organization_fixture(plan: "pro")
      team_org = organization_fixture(plan: "team")
      biz_org = organization_fixture(plan: "business")

      for feature <- [:status_page_customization, :custom_domain, :maintenance_scheduling] do
        refute Billing.can_use_feature?(free_org, feature)
        refute Billing.can_use_feature?(pro_org, feature)
        assert Billing.can_use_feature?(team_org, feature)
        assert Billing.can_use_feature?(biz_org, feature)
      end
    end
  end

  describe "allowed_channel_types/1" do
    test "all plans allow exactly the 4 supported types" do
      for plan <- ["free", "pro", "team", "business"] do
        types = Billing.allowed_channel_types(plan)
        assert types == ["email", "slack", "discord", "telegram"]
      end
    end

    test "rejects unsupported types regardless of plan" do
      for plan <- ["free", "pro", "team", "business"] do
        types = Billing.allowed_channel_types(plan)
        refute "webhook" in types
        refute "sms" in types
        refute "phone" in types
        refute "teams" in types
        refute "mattermost" in types
      end
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

    test "handle_webhook_event subscription.activated with business price ID" do
      org = organization_fixture()

      data = %{
        "id" => "sub_biz_123",
        "customer_id" => "ctm_biz_123",
        "custom_data" => %{"organization_id" => org.id, "plan" => "business"},
        "items" => [%{"price" => %{"id" => "pri_business_test"}}],
        "current_billing_period" => %{
          "starts_at" => "2026-03-30T00:00:00Z",
          "ends_at" => "2026-04-30T00:00:00Z"
        }
      }

      assert {:ok, sub} = Billing.handle_webhook_event("subscription.activated", data)
      assert sub.plan == "business"

      updated_org = Organizations.get_organization(org.id)
      assert updated_org.plan == "business"
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

  describe "cancel_active_subscription/1" do
    test "cancels subscription and downgrades org to free" do
      org = organization_fixture(plan: "pro")
      {:ok, _sub} = insert_subscription(org, "pro", "active")

      Process.put(:paddle_cancel_subscription, {:ok, %{}})

      case Billing.cancel_active_subscription(org) do
        {:ok, sub} ->
          assert sub.status == "cancelled"

          # Verify org plan was downgraded to free
          updated_org = Organizations.get_organization(org.id)
          assert updated_org.plan == "free"

        _ ->
          flunk("Expected successful cancellation")
      end
    end

    test "returns error when no active subscription" do
      org = organization_fixture()
      assert {:error, :no_active_subscription} = Billing.cancel_active_subscription(org)
    end
  end

  describe "create_checkout_session/3" do
    test "creates checkout for pro plan" do
      org = organization_fixture()
      Process.put(:paddle_create_transaction, {:ok, %{"id" => "txn_test", "checkout" => %{"url" => "https://checkout.paddle.com/test"}}})

      assert {:ok, %{checkout_url: url, transaction_id: txn}} = Billing.create_checkout_session(org, "pro", "monthly")
      assert url =~ "paddle.com"
      assert txn == "txn_test"
    end

    test "creates checkout for business plan" do
      org = organization_fixture()
      Process.put(:paddle_create_transaction, {:ok, %{"id" => "txn_biz", "checkout" => %{"url" => "https://checkout.paddle.com/biz"}}})

      assert {:ok, %{checkout_url: _, transaction_id: "txn_biz"}} = Billing.create_checkout_session(org, "business", "annual")
    end

    test "rejects invalid plan" do
      org = organization_fixture()
      assert {:error, :invalid_plan} = Billing.create_checkout_session(org, "enterprise", "monthly")
    end

    test "rejects invalid interval" do
      org = organization_fixture()
      assert {:error, :invalid_plan} = Billing.create_checkout_session(org, "pro", "biweekly")
    end
  end

  describe "effective_limit/3" do
    test "returns base plan limit without add-ons" do
      org = organization_fixture(plan: "pro")
      assert Billing.effective_limit(org.id, "pro", :monitors) == 30
    end

    test "adds extra monitors from add-ons" do
      org = organization_fixture(plan: "pro")
      Billing.set_add_on(org.id, "extra_monitors", 10)

      assert Billing.effective_limit(org.id, "pro", :monitors) == 40
    end

    test "returns :unlimited for unlimited resources" do
      org = organization_fixture(plan: "team")
      assert Billing.effective_limit(org.id, "team", :alert_channels) == :unlimited
    end
  end

  describe "add-on management" do
    test "set_add_on creates and updates" do
      org = organization_fixture(plan: "pro")

      assert {:ok, _} = Billing.set_add_on(org.id, "extra_monitors", 5)
      assert Billing.get_add_on_quantity(org.id, "extra_monitors") == 5

      assert {:ok, _} = Billing.set_add_on(org.id, "extra_monitors", 10)
      assert Billing.get_add_on_quantity(org.id, "extra_monitors") == 10
    end

    test "set_add_on with 0 removes" do
      org = organization_fixture(plan: "pro")

      Billing.set_add_on(org.id, "extra_monitors", 5)
      Billing.set_add_on(org.id, "extra_monitors", 0)

      assert Billing.get_add_on_quantity(org.id, "extra_monitors") == 0
    end

    test "add_on_monthly_cost calculates correctly" do
      org = organization_fixture(plan: "pro")

      Billing.set_add_on(org.id, "extra_monitors", 10)    # 10 * 20 = 200 cents
      Billing.set_add_on(org.id, "extra_fast_slots", 2)   # 2 * 100 = 200 cents

      assert Billing.add_on_monthly_cost(org.id) == 400
    end
  end

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
