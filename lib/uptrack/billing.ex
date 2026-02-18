defmodule Uptrack.Billing do
  @moduledoc """
  Billing context — manages subscriptions and Paddle checkout flow.

  Public API for the billing domain. Schemas and HTTP client are internal.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Billing.{Subscription, PaddleClient}
  alias Uptrack.Organizations
  alias Uptrack.Organizations.Organization

  require Logger

  # --- Plan limits (pure data) ---

  @plan_limits %{
    "free" => %{monitors: 10, alert_channels: 2, status_pages: 1, team_members: 1, min_interval: 180},
    "pro" => %{monitors: 25, alert_channels: :unlimited, status_pages: 3, team_members: 5, min_interval: 30},
    "team" => %{monitors: 150, alert_channels: :unlimited, status_pages: :unlimited, team_members: :unlimited, min_interval: 30}
  }

  def plan_limits(plan), do: Map.get(@plan_limits, plan, @plan_limits["free"])

  def plan_limit(plan, resource), do: plan_limits(plan)[resource]

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

    if interval >= min do
      :ok
    else
      {:error, "The #{String.capitalize(org.plan)} plan requires a minimum check interval of #{min} seconds. Upgrade for faster checks."}
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

  # --- Checkout flow ---

  @doc """
  Creates a Paddle transaction and returns the checkout URL.

  Paddle auto-creates customers during checkout, so no pre-creation needed.
  The transaction is created in draft status; Paddle.js opens the checkout overlay.
  """
  def create_checkout_session(%Organization{} = organization, plan) when plan in ["pro", "team"] do
    config = paddle_config()
    price_id = price_id_for_plan(plan, config)

    case PaddleClient.create_transaction(%{
           items: [%{price_id: price_id, quantity: 1}],
           custom_data: %{
             organization_id: organization.id,
             plan: plan
           }
         }) do
      {:ok, %{"id" => txn_id, "checkout" => %{"url" => url}}} ->
        {:ok, %{checkout_url: url, transaction_id: txn_id}}

      {:ok, data} ->
        # Fallback: construct checkout URL from transaction ID
        checkout_url = "#{config[:checkout_url]}?_ptxn=#{data["id"]}"
        {:ok, %{checkout_url: checkout_url, transaction_id: data["id"]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_checkout_session(_organization, _plan), do: {:error, :invalid_plan}

  @doc """
  Creates a Paddle customer portal session for managing billing.
  Returns {:ok, url} or {:error, reason}.
  """
  def create_portal_session(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      %{paddle_customer_id: nil} ->
        {:error, :no_customer_id}

      subscription ->
        case PaddleClient.create_portal_session(subscription.paddle_customer_id) do
          {:ok, %{"urls" => %{"general" => %{"overview" => url}}}} ->
            {:ok, url}

          {:ok, data} ->
            # Fallback: try different response shapes
            url = get_in(data, ["urls", "general", "overview"]) || data["id"]
            {:ok, url}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # --- Subscription management ---

  def cancel_active_subscription(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        with {:ok, _} <- PaddleClient.cancel_subscription(subscription.paddle_subscription_id, %{effective_from: "immediately"}) do
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

  # --- Webhook handlers (called from WebhookController) ---

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

        # Extract plan from items if present (plan changes come through here too)
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

    # Extract price_id from items to determine plan
    price_id =
      case data["items"] do
        [%{"price" => %{"id" => pid}} | _] -> pid
        _ -> nil
      end

    plan = plan_for_price_id(price_id)

    # Parse billing period
    {period_start, period_end} = parse_billing_period(data["current_billing_period"])

    case get_subscription_by_paddle_id(paddle_sub_id) do
      nil ->
        if is_nil(org_id) do
          Logger.error("Webhook: subscription.activated without organization_id in custom_data")
          {:error, :missing_organization_id}
        else
          %Subscription{}
          |> Subscription.changeset(%{
            organization_id: org_id,
            paddle_subscription_id: paddle_sub_id,
            paddle_customer_id: customer_id,
            plan: plan,
            status: status,
            current_period_start: period_start,
            current_period_end: period_end
          })
          |> AppRepo.insert()
          |> tap(fn
            {:ok, sub} -> update_organization_plan(sub.organization_id, plan)
            _ -> :ok
          end)
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
        org
        |> Organization.changeset(%{plan: plan})
        |> AppRepo.update()
    end
  end

  defp price_id_for_plan("pro", config), do: config[:price_id_pro]
  defp price_id_for_plan("team", config), do: config[:price_id_team]

  defp plan_for_price_id(nil), do: "pro"

  defp plan_for_price_id(price_id) do
    config = paddle_config()

    cond do
      price_id == config[:price_id_pro] -> "pro"
      price_id == config[:price_id_team] -> "team"
      true -> "pro"
    end
  end

  # Paddle sends "trialing" status; map to our schema values
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

  defp paddle_config do
    Application.get_env(:uptrack, :paddle) ||
      raise "Paddle configuration not set"
  end
end
