defmodule Uptrack.Billing do
  @moduledoc """
  Billing context — manages subscriptions and payment provider checkout flow.

  Public API for the billing domain. Delegates to Paddle for checkout,
  cancellation, and portal operations.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Billing.PaddleClient
  alias Uptrack.Billing.Subscription
  alias Uptrack.Organizations
  alias Uptrack.Organizations.Organization

  require Logger

  # --- Plan limits (pure data) ---

  @plan_limits %{
    "free" => %{
      monitors: 10, alert_channels: 2, status_pages: 5, team_members: 1,
      min_interval: 180, fast_monitors: 1, webhooks_per_monitor: 1,
      regions: 3, retention_days: 180, sms_alerts: 0, subscribers: 100,
      notify_only_seats: 0
    },
    "pro" => %{
      monitors: 15, alert_channels: 5, status_pages: 5, team_members: 3,
      min_interval: 60, fast_monitors: 1, webhooks_per_monitor: 2,
      regions: 5, retention_days: 730, sms_alerts: 30, subscribers: 1_000,
      notify_only_seats: 1
    },
    "team" => %{
      monitors: 60, alert_channels: :unlimited, status_pages: :unlimited, team_members: 5,
      min_interval: 30, fast_monitors: :unlimited, webhooks_per_monitor: 5,
      regions: 15, retention_days: 730, sms_alerts: 100, subscribers: 5_000,
      notify_only_seats: 3
    },
    "business" => %{
      monitors: 300, alert_channels: :unlimited, status_pages: :unlimited, team_members: 15,
      min_interval: 30, fast_monitors: :unlimited, webhooks_per_monitor: 10,
      regions: 15, retention_days: 1825, sms_alerts: 200, subscribers: 10_000,
      notify_only_seats: 5
    }
  }

  @all_plans Map.keys(@plan_limits)
  @paid_plans @all_plans -- ["free"]

  def all_plans, do: @all_plans
  def paid_plans, do: @paid_plans

  def plan_limits(plan), do: Map.get(@plan_limits, plan, @plan_limits["free"])

  def plan_limit(plan, resource), do: plan_limits(plan)[resource]

  def payment_provider_name, do: "paddle"

  # --- Feature gating ---

  @business_features ~w(whitelabel custom_email_sender sso rbac priority_support)a
  @team_features ~w(status_page_customization custom_domain password_protection
                     incident_updates maintenance_scheduling search_engine_optout
                     weekly_reports mattermost)a

  @doc """
  Checks if the organization's plan includes a specific feature.
  Returns true or false.
  """
  def can_use_feature?(%Organization{plan: plan}, feature) when feature in @business_features do
    plan == "business"
  end

  def can_use_feature?(%Organization{plan: plan}, feature) when feature in @team_features do
    plan in ["team", "business"]
  end

  def can_use_feature?(_org, _feature), do: true

  @doc """
  Returns the list of allowed alert channel types for a plan.
  """
  def allowed_channel_types("free"), do: ["email"]
  def allowed_channel_types("pro"), do: ["email", "slack", "ms_teams", "discord", "telegram", "webhook"]
  def allowed_channel_types(_plan), do: :all

  # --- Plan enforcement ---

  @doc """
  Checks if the organization can create a new resource of the given type.
  Returns :ok or {:error, message}.
  """
  def check_plan_limit(%Organization{} = org, resource) when resource in [:monitors, :alert_channels, :status_pages, :team_members] do
    limit = plan_limit(org.plan, resource)

    if limit == :unlimited do
      :ok
    else
      current_count = count_resource(org.id, resource)

      if current_count < limit do
        :ok
      else
        {:error, "You've reached the #{resource_label(resource)} limit for the #{String.capitalize(org.plan)} plan (#{limit}). Upgrade for more."}
      end
    end
  end

  @doc """
  Checks if the requested check interval meets the plan minimum.
  Returns :ok or {:error, message}.
  """
  def check_interval_limit(%Organization{} = org, interval) when is_integer(interval) do
    min = plan_limit(org.plan, :min_interval)

    cond do
      interval >= min ->
        :ok

      # Below plan minimum — check if fast monitor slot is available (only for intervals ≥ 30s)
      interval >= 30 ->
        fast_limit = plan_limit(org.plan, :fast_monitors)

        cond do
          fast_limit == :unlimited ->
            :ok

          is_integer(fast_limit) and Uptrack.Monitoring.count_fast_monitors(org.id) < fast_limit ->
            :ok

          true ->
            {:error, "Your plan includes #{fast_limit} Fast Monitor slot (30s). You've used yours — upgrade to Team for unlimited 30s monitors."}
        end

      true ->
        {:error, "The minimum supported check interval is 30 seconds."}
    end
  end

  defp count_resource(org_id, :monitors), do: Uptrack.Monitoring.count_monitors(org_id)
  defp count_resource(org_id, :alert_channels), do: Uptrack.Monitoring.count_alert_channels(org_id)
  defp count_resource(org_id, :status_pages), do: Uptrack.Monitoring.count_status_pages(org_id)
  defp count_resource(org_id, :team_members), do: Uptrack.Teams.count_members(org_id)

  defp resource_label(:monitors), do: "monitor"
  defp resource_label(:alert_channels), do: "alert channel"
  defp resource_label(:status_pages), do: "status page"
  defp resource_label(:team_members), do: "team member"

  # --- Subscription queries ---

  def get_active_subscription(organization_id) do
    from(s in Subscription,
      where: s.organization_id == ^organization_id,
      where: s.status in ["active", "trialing"],
      order_by: [desc: s.inserted_at],
      limit: 1
    )
    |> AppRepo.one()
  end

  def get_subscription_by_paddle_id(paddle_subscription_id) do
    AppRepo.get_by(Subscription, paddle_subscription_id: paddle_subscription_id)
  end

  def get_subscription_by_provider_id(provider_subscription_id) do
    AppRepo.get_by(Subscription, provider_subscription_id: provider_subscription_id)
  end

  @doc "Find subscription by either legacy paddle_subscription_id or generic provider_subscription_id."
  def find_subscription(subscription_id) do
    get_subscription_by_provider_id(subscription_id) ||
      get_subscription_by_paddle_id(subscription_id)
  end

  # --- Checkout flow (delegates to configured provider) ---

  @doc """
  Creates a checkout session via the configured payment provider.
  Returns {:ok, %{checkout_url, transaction_id}} or {:error, reason}.
  """
  def create_checkout_session(organization, plan, interval \\ "monthly")

  def create_checkout_session(%Organization{} = organization, plan, interval)
      when plan in @paid_plans and interval in ["monthly", "annual"] do
    config = paddle_config()
    price_id = price_id_for_plan(plan, interval, config)
    success_url = Application.get_env(:uptrack, :frontend_url, "https://uptrack.app")

    case PaddleClient.create_transaction(%{
           items: [%{price_id: price_id, quantity: 1}],
           custom_data: %{organization_id: organization.id, plan: plan},
           checkout: %{url: "#{success_url}/dashboard/settings?billing=success"}
         }) do
      {:ok, %{"id" => txn_id, "checkout" => %{"url" => url}}} ->
        {:ok, %{checkout_url: url, transaction_id: txn_id}}

      {:ok, data} ->
        checkout_url = "#{config[:checkout_url]}?_ptxn=#{data["id"]}"
        {:ok, %{checkout_url: checkout_url, transaction_id: data["id"]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_checkout_session(_organization, _plan, _interval), do: {:error, :invalid_plan}

  @doc """
  Creates a customer portal session for managing billing.
  Returns {:ok, url} or {:error, reason}.
  """
  def create_portal_session(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        customer_id = subscription.provider_customer_id || subscription.paddle_customer_id

        if is_nil(customer_id) do
          {:error, :no_customer_id}
        else
          case PaddleClient.create_portal_session(customer_id) do
            {:ok, %{"urls" => %{"general" => %{"overview" => url}}}} -> {:ok, url}
            {:ok, data} -> {:ok, get_in(data, ["urls", "general", "overview"]) || data["id"]}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  # --- Subscription management ---

  @doc """
  Switches an active subscription from one paid plan to another.
  Returns {:ok, plan} on success or {:error, reason} on failure.
  """
  def update_subscription_plan(%Organization{} = organization, plan) when plan in @paid_plans do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        sub_id = subscription.provider_subscription_id || subscription.paddle_subscription_id
        config = paddle_config()
        price_id = price_id_for_plan(plan, "monthly", config)

        case PaddleClient.update_subscription(sub_id, %{
               items: [%{price_id: price_id, quantity: 1}],
               proration_billing_mode: "prorated_immediately"
             }) do
          {:ok, _} ->
            subscription
            |> Subscription.changeset(%{plan: plan})
            |> AppRepo.update()
            |> case do
              {:ok, _} ->
                update_organization_plan(organization.id, plan)
                {:ok, plan}

              {:error, _} = err ->
                err
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def update_subscription_plan(_organization, _plan), do: {:error, :invalid_plan}

  def cancel_active_subscription(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        sub_id = subscription.provider_subscription_id || subscription.paddle_subscription_id

        with {:ok, _} <- PaddleClient.cancel_subscription(sub_id, %{effective_from: "immediately"}) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          subscription
          |> Subscription.changeset(%{status: "cancelled", cancelled_at: now})
          |> AppRepo.update()
          |> tap(fn
            {:ok, _} -> update_organization_plan(organization.id, "free")
            _ -> :ok
          end)
        end
    end
  end

  # --- Paddle webhook handlers ---

  def handle_webhook_event("subscription.created", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.activated", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.trialing", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.canceled", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.canceled for unknown subscription #{data["id"]}")
        :ok

      %{status: "cancelled"} = subscription ->
        # Already cancelled (retry) — skip redundant org plan update
        {:ok, subscription}

      subscription ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        subscription
        |> Subscription.changeset(%{status: "cancelled", cancelled_at: now})
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} -> update_organization_plan(sub.organization_id, "free")
          _ -> :ok
        end)
    end
  end

  def handle_webhook_event("subscription.updated", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.updated for unknown subscription #{data["id"]}")
        :ok

      subscription ->
        {period_start, period_end} = parse_billing_period(data["current_billing_period"])
        status = normalize_status(data["status"])

        price_id =
          case data["items"] do
            [%{"price" => %{"id" => pid}} | _] -> pid
            _ -> nil
          end

        plan = if price_id, do: plan_for_price_id(price_id), else: subscription.plan

        subscription
        |> Subscription.changeset(%{
          plan: plan,
          status: status,
          current_period_start: period_start,
          current_period_end: period_end
        })
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} ->
            if sub.plan != subscription.plan do
              update_organization_plan(sub.organization_id, sub.plan)
            end
          _ -> :ok
        end)
    end
  end

  def handle_webhook_event("subscription.past_due", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.past_due for unknown subscription #{data["id"]}")
        :ok

      %{status: "past_due"} = subscription ->
        {:ok, subscription}

      subscription ->
        subscription
        |> Subscription.changeset(%{status: "past_due"})
        |> AppRepo.update()
    end
  end

  def handle_webhook_event("transaction.payment_failed", data) do
    sub_id = data["subscription_id"]

    if sub_id do
      case get_subscription_by_paddle_id(sub_id) do
        nil -> :ok
        %{status: "past_due"} = subscription -> {:ok, subscription}
        subscription ->
          subscription
          |> Subscription.changeset(%{status: "past_due"})
          |> AppRepo.update()
      end
    else
      :ok
    end
  end

  def handle_webhook_event(event_name, _data) do
    Logger.debug("Ignoring Paddle webhook event: #{event_name}")
    :ok
  end

  # --- Private helpers ---

  defp handle_subscription_activated(data) do
    paddle_sub_id = data["id"]
    customer_id = data["customer_id"]
    custom_data = data["custom_data"] || %{}
    org_id = custom_data["organization_id"]
    status = normalize_status(data["status"])

    price_id =
      case data["items"] do
        [%{"price" => %{"id" => pid}} | _] -> pid
        _ -> nil
      end

    plan = plan_for_price_id(price_id)
    {period_start, period_end} = parse_billing_period(data["current_billing_period"])

    case get_subscription_by_paddle_id(paddle_sub_id) do
      nil ->
        if is_nil(org_id) do
          Logger.error("Webhook: subscription.activated without organization_id in custom_data")
          {:error, :missing_organization_id}
        else
          result =
            %Subscription{}
            |> Subscription.changeset(%{
              organization_id: org_id,
              paddle_subscription_id: paddle_sub_id,
              paddle_customer_id: customer_id,
              provider: "paddle",
              plan: plan,
              status: status,
              current_period_start: period_start,
              current_period_end: period_end
            })
            |> AppRepo.insert(
              on_conflict: :nothing,
              conflict_target: :paddle_subscription_id
            )

          case result do
            {:ok, %{id: nil}} ->
              # Conflict: another webhook already inserted this subscription
              :ok

            {:ok, sub} ->
              update_organization_plan(sub.organization_id, plan)
              {:ok, sub}

            error ->
              error
          end
        end

      existing ->
        existing
        |> Subscription.changeset(%{
          plan: plan,
          status: status,
          current_period_start: period_start,
          current_period_end: period_end,
          cancelled_at: nil
        })
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} -> update_organization_plan(sub.organization_id, plan)
          _ -> :ok
        end)
    end
  end

  defp update_organization_plan(organization_id, plan) do
    case Organizations.get_organization(organization_id) do
      nil ->
        Logger.error("Cannot update plan: organization #{organization_id} not found")

      org ->
        result =
          org
          |> Organization.changeset(%{plan: plan})
          |> AppRepo.update()

        with {:ok, _} <- result do
          enforce_plan_limits(organization_id, plan)
        end

        result
    end
  end

  defp enforce_plan_limits(organization_id, plan) do
    monitor_limit = plan_limit(plan, :monitors)

    if is_integer(monitor_limit) do
      excess = Uptrack.Monitoring.select_excess_monitors(organization_id, monitor_limit)

      if excess != [] do
        ids = Enum.map(excess, & &1.id)
        count = Uptrack.Monitoring.pause_monitors(ids)
        Logger.info("Paused #{count} monitors for org #{organization_id} after downgrade to #{plan}")
      end
    end
  end

  defp plan_for_price_id(nil) do
    Logger.warning("Paddle webhook received nil price_id, falling back to pro plan")
    "pro"
  end

  defp plan_for_price_id(price_id) do
    config = paddle_config()

    cond do
      price_id == config[:price_id_pro] -> "pro"
      price_id == config[:price_id_pro_annual] -> "pro"
      price_id == config[:price_id_team] -> "team"
      price_id == config[:price_id_team_annual] -> "team"
      price_id == config[:price_id_business] -> "business"
      price_id == config[:price_id_business_annual] -> "business"
      true ->
        Logger.warning("Unknown Paddle price_id #{inspect(price_id)}, falling back to pro plan")
        "pro"
    end
  end

  defp normalize_status("trialing"), do: "trialing"
  defp normalize_status(_), do: "active"

  defp parse_billing_period(nil), do: {nil, nil}

  defp parse_billing_period(%{"starts_at" => starts_at, "ends_at" => ends_at}) do
    {parse_timestamp(starts_at), parse_timestamp(ends_at)}
  end

  defp parse_billing_period(_), do: {nil, nil}

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp price_id_for_plan("pro", "annual", config), do: config[:price_id_pro_annual] || config[:price_id_pro]
  defp price_id_for_plan("team", "annual", config), do: config[:price_id_team_annual] || config[:price_id_team]
  defp price_id_for_plan("business", "annual", config), do: config[:price_id_business_annual] || config[:price_id_business]
  defp price_id_for_plan("pro", _interval, config), do: config[:price_id_pro]
  defp price_id_for_plan("team", _interval, config), do: config[:price_id_team]
  defp price_id_for_plan("business", _interval, config), do: config[:price_id_business]

  defp paddle_config do
    Application.get_env(:uptrack, :paddle) ||
      raise "Paddle configuration not set"
  end
end
