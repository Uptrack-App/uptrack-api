defmodule Uptrack.Billing.Creem.CreemProvider do
  @moduledoc """
  Creem implementation of the PaymentProvider behaviour.

  Creem uses hosted checkout (redirect/popup) — no overlay SDK.
  The frontend opens the checkout URL in a popup window.
  """

  @behaviour Uptrack.Billing.PaymentProvider

  alias Uptrack.Billing.Creem.CreemClient

  require Logger

  @impl true
  def create_checkout(organization, plan, interval \\ "monthly")

  def create_checkout(organization, plan, interval) when plan in ["pro", "team"] do
    config = creem_config()
    product_id = product_id_for_plan(plan, interval, config)

    case CreemClient.create_checkout(%{
           product_id: product_id,
           success_url: config[:success_url] || "https://uptrack.app/dashboard/settings?billing=success&plan=#{plan}",
           metadata: %{
             organization_id: organization.id,
             plan: plan
           }
         }) do
      {:ok, %{"id" => checkout_id, "checkout_url" => url}} ->
        {:ok, %{checkout_url: url, transaction_id: checkout_id}}

      {:ok, %{"checkout_url" => url} = data} ->
        {:ok, %{checkout_url: url, transaction_id: data["id"] || ""}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_checkout(_organization, _plan, _interval), do: {:error, :invalid_plan}

  @impl true
  def cancel_subscription(subscription_id) do
    CreemClient.cancel_subscription(subscription_id, "immediate")
  end

  @impl true
  def update_subscription(subscription_id, plan) when plan in ["pro", "team"] do
    config = creem_config()
    product_id = product_id_for_plan(plan, "monthly", config)

    CreemClient.upgrade_subscription(subscription_id, %{
      product_id: product_id,
      proration: true
    })
  end

  def update_subscription(_subscription_id, _plan), do: {:error, :invalid_plan}

  @impl true
  def create_portal_session(customer_id) do
    case CreemClient.create_billing_portal(customer_id) do
      {:ok, %{"portal_url" => url}} -> {:ok, url}
      {:ok, data} -> {:ok, data["portal_url"] || data["url"] || ""}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def handle_webhook(event_type, data) do
    case event_type do
      "subscription.active" -> handle_subscription_active(data)
      "subscription.paid" -> handle_subscription_active(data)
      "subscription.trialing" -> handle_subscription_active(data)
      "subscription.canceled" -> handle_subscription_cancelled(data)
      "subscription.scheduled_cancel" -> handle_subscription_cancelled(data)
      "subscription.expired" -> handle_subscription_cancelled(data)
      "subscription.past_due" -> handle_subscription_past_due(data)
      "subscription.paused" -> handle_subscription_past_due(data)
      "checkout.completed" -> handle_checkout_completed(data)
      _ ->
        Logger.debug("Ignoring Creem webhook event: #{event_type}")
        {:error, :unhandled_event}
    end
  end

  # --- Private ---

  defp handle_checkout_completed(data) do
    # Creem checkout.completed payload structure:
    # data.subscription.id, data.customer (string or nested), data.metadata, data.order.product
    sub = data["subscription"] || %{}
    sub_id = sub["id"] || data["subscription_id"]
    customer_id = extract_customer_id(data)
    metadata = data["metadata"] || %{}
    org_id = metadata["organization_id"]
    product_id = get_in(data, ["order", "product"]) || data["product_id"]
    plan = metadata["plan"] || plan_for_product_id(product_id)

    Logger.info("Creem checkout.completed: sub_id=#{sub_id} org_id=#{org_id} plan=#{plan}")

    if sub_id do
      {:ok, %{
        provider: "creem",
        provider_subscription_id: sub_id,
        provider_customer_id: customer_id,
        organization_id: org_id,
        plan: plan,
        status: "active"
      }}
    else
      {:error, :unhandled_event}
    end
  end

  defp handle_subscription_active(data) do
    # Creem subscription.active: data.id is sub ID, data.customer/product are nested
    sub_id = data["id"] || data["subscription_id"]
    customer_id = extract_customer_id(data)
    metadata = data["metadata"] || %{}
    org_id = metadata["organization_id"]
    product_id = extract_product_id(data)
    plan = metadata["plan"] || plan_for_product_id(product_id)

    Logger.info("Creem subscription.active: sub_id=#{sub_id} org_id=#{org_id} plan=#{plan}")

    {:ok, %{
      provider: "creem",
      provider_subscription_id: sub_id,
      provider_customer_id: customer_id,
      organization_id: org_id,
      plan: plan,
      status: "active",
      current_period_start: parse_timestamp(data["current_period_start"] || data["created_at"]),
      current_period_end: parse_timestamp(data["current_period_end"] || data["updated_at"])
    }}
  end

  defp handle_subscription_cancelled(data) do
    sub_id = data["id"] || data["subscription_id"]

    {:ok, %{
      provider: "creem",
      provider_subscription_id: sub_id,
      status: "cancelled"
    }}
  end

  defp handle_subscription_past_due(data) do
    sub_id = data["id"] || data["subscription_id"]

    {:ok, %{
      provider: "creem",
      provider_subscription_id: sub_id,
      status: "past_due"
    }}
  end

  defp extract_customer_id(data) do
    case data["customer"] do
      %{"id" => id} -> id
      id when is_binary(id) -> id
      _ -> data["customer_id"]
    end
  end

  defp extract_product_id(data) do
    case data["product"] do
      %{"id" => id} -> id
      id when is_binary(id) -> id
      _ -> get_in(data, ["order", "product"]) || data["product_id"]
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_integer(ts) do
    # Creem sends timestamps as Unix milliseconds
    ts
    |> div(1000)
    |> DateTime.from_unix!()
    |> DateTime.truncate(:second)
  end

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_timestamp(_), do: nil

  defp product_id_for_plan("pro", "annual", config), do: config[:product_id_pro_annual] || config[:product_id_pro]
  defp product_id_for_plan("team", "annual", config), do: config[:product_id_team_annual] || config[:product_id_team]
  defp product_id_for_plan("pro", _interval, config), do: config[:product_id_pro]
  defp product_id_for_plan("team", _interval, config), do: config[:product_id_team]

  defp plan_for_product_id(nil), do: "pro"

  defp plan_for_product_id(product_id) do
    config = creem_config()

    cond do
      product_id == config[:product_id_pro] -> "pro"
      product_id == config[:product_id_pro_annual] -> "pro"
      product_id == config[:product_id_team] -> "team"
      product_id == config[:product_id_team_annual] -> "team"
      true ->
        Logger.warning("Unknown Creem product_id #{inspect(product_id)}, falling back to pro")
        "pro"
    end
  end

  defp creem_config do
    Application.get_env(:uptrack, :creem) ||
      raise "Creem configuration not set"
  end
end
