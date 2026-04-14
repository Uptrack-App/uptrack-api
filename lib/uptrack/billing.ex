defmodule Uptrack.Billing do
  @moduledoc """
  Billing context — public API for the billing domain.

  Delegates pure plan logic to `Billing.Plans`, webhook handling to
  `Billing.Webhooks`, and owns subscription queries, checkout, and
  add-on management directly.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Billing.AddOn
  alias Uptrack.Billing.PaddleClient
  alias Uptrack.Billing.Plans
  alias Uptrack.Billing.Subscription
  alias Uptrack.Billing.Webhooks
  alias Uptrack.Organizations.Organization

  require Logger

  @paid_plans Plans.paid_plans()

  # --- Delegated pure plan API ---

  defdelegate all_plans, to: Plans
  defdelegate paid_plans, to: Plans
  defdelegate plan_limits(plan), to: Plans
  defdelegate plan_limit(plan, resource), to: Plans
  defdelegate can_use_feature?(org, feature), to: Plans
  defdelegate allowed_channel_types(plan), to: Plans
  defdelegate check_region_limit(org, region_count), to: Plans

  def payment_provider_name, do: "paddle"

  # --- Interval enforcement (bridges pure Plans with DB counts) ---

  @doc """
  Checks if the requested check interval meets the plan minimum.
  Fetches slot counts from DB lazily (only when needed) and delegates to Plans.
  Returns :ok or {:error, message}.
  """
  def check_interval_limit(%Organization{} = org, interval) when is_integer(interval) do
    counts =
      if interval <= 30 do
        %{quick_monitors: Uptrack.Monitoring.count_quick_monitors(org.id)}
      else
        %{}
      end

    Plans.check_interval_limit(org, interval, counts)
  end

  # --- Plan enforcement (bridges pure Plans with DB counts) ---

  @doc """
  Checks if the organization can create a new resource of the given type.
  Returns :ok or {:error, message}.
  """
  def check_plan_limit(%Organization{} = org, resource)
      when resource in [:monitors, :alert_channels, :status_pages, :team_members] do
    limit = effective_limit(org.id, org.plan, resource)

    if limit == :unlimited do
      :ok
    else
      current_count = count_resource(org.id, resource)

      if current_count < limit do
        :ok
      else
        {:error, "You've reached the #{resource_label(resource)} limit for your plan (#{limit}). Upgrade or add extras."}
      end
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

  # --- Add-on management ---

  @doc "Lists all add-ons for an organization."
  def list_add_ons(organization_id) do
    from(a in AddOn, where: a.organization_id == ^organization_id)
    |> AppRepo.all()
  end

  @doc "Gets add-on quantity for a specific type. Returns 0 if none."
  def get_add_on_quantity(organization_id, type) do
    case AppRepo.get_by(AddOn, organization_id: organization_id, type: type) do
      nil -> 0
      add_on -> add_on.quantity
    end
  end

  @doc "Sets add-on quantity (upsert). Quantity of 0 removes the add-on."
  def set_add_on(organization_id, type, quantity) when is_integer(quantity) and quantity >= 0 do
    case AppRepo.get_by(AddOn, organization_id: organization_id, type: type) do
      nil when quantity > 0 ->
        %AddOn{}
        |> AddOn.changeset(%{organization_id: organization_id, type: type, quantity: quantity})
        |> AppRepo.insert()

      nil ->
        {:ok, nil}

      existing when quantity == 0 ->
        AppRepo.delete(existing)

      existing ->
        existing
        |> AddOn.changeset(%{quantity: quantity})
        |> AppRepo.update()
    end
  end

  @doc """
  Returns the effective limit for a resource, including add-ons.
  """
  def effective_limit(organization_id, plan, resource) do
    base = Plans.plan_limit(plan, resource)

    if base == :unlimited do
      :unlimited
    else
      add_on_type = Plans.resource_to_add_on(resource)
      extra = if add_on_type, do: get_add_on_quantity(organization_id, add_on_type), else: 0
      base + extra
    end
  end

  @doc "Calculates total monthly add-on cost in cents."
  def add_on_monthly_cost(organization_id) do
    list_add_ons(organization_id)
    |> Enum.reduce(0, fn add_on, acc ->
      acc + add_on.quantity * AddOn.unit_price(add_on.type)
    end)
  end

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

  # --- Checkout flow ---

  @doc """
  Creates a checkout session via Paddle.
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
  def update_subscription_plan(%Organization{} = organization, plan)
      when plan in @paid_plans do
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
                Webhooks.update_organization_plan(organization.id, plan)
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
            {:ok, _} -> Webhooks.update_organization_plan(organization.id, "free")
            _ -> :ok
          end)
        end
    end
  end

  # --- Webhook delegation ---

  defdelegate handle_webhook_event(event, data), to: Webhooks, as: :handle_event

  # --- Private helpers ---

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
