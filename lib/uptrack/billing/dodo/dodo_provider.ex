defmodule Uptrack.Billing.Dodo.DodoProvider do
  @moduledoc """
  Dodo Payments implementation of the PaymentProvider behaviour.

  Adapts DodoClient responses to the generic PaymentProvider contract.
  """

  @behaviour Uptrack.Billing.PaymentProvider

  alias Uptrack.Billing.Dodo.DodoClient

  require Logger

  @impl true
  def create_checkout(organization, plan, interval \\ "monthly")

  def create_checkout(organization, plan, interval) when plan in ["pro", "team"] do
    config = dodo_config()
    product_id = product_id_for_plan(plan, interval, config)

    case DodoClient.create_subscription(%{
           product_id: product_id,
           quantity: 1,
           payment_link: true,
           customer: %{
             customer_id: organization.id
           },
           metadata: %{
             organization_id: organization.id,
             plan: plan
           },
           return_url: config[:return_url] || "https://uptrack.app/dashboard/settings?billing=success&plan=#{plan}"
         }) do
      {:ok, %{"subscription_id" => sub_id, "payment_link" => url}} ->
        {:ok, %{checkout_url: url, transaction_id: sub_id}}

      {:ok, %{"subscription_id" => sub_id} = data} ->
        url = data["payment_link"] || data["checkout_url"] || ""
        {:ok, %{checkout_url: url, transaction_id: sub_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_checkout(_organization, _plan, _interval), do: {:error, :invalid_plan}

  @impl true
  def cancel_subscription(subscription_id) do
    DodoClient.update_subscription(subscription_id, %{
      status: "cancelled"
    })
  end

  @impl true
  def update_subscription(subscription_id, plan) when plan in ["pro", "team"] do
    config = dodo_config()
    product_id = product_id_for_plan(plan, "monthly", config)

    # Dodo doesn't have a direct plan change API like Paddle's proration.
    # We cancel at next billing and create a new subscription.
    # For now, use update_subscription to set cancel_at_next_billing_date,
    # then the frontend can initiate a new checkout.
    # TODO: Verify Dodo's plan change flow once dashboard is set up.
    DodoClient.update_subscription(subscription_id, %{
      metadata: %{plan: plan, product_id: product_id}
    })
  end

  def update_subscription(_subscription_id, _plan), do: {:error, :invalid_plan}

  @impl true
  def create_portal_session(customer_id) do
    DodoClient.create_portal_session(customer_id)
  end

  @impl true
  def handle_webhook(event_type, data) do
    case event_type do
      "subscription.active" -> handle_subscription_activated(data)
      "subscription.renewed" -> handle_subscription_activated(data)
      "subscription.cancelled" -> handle_subscription_cancelled(data)
      "subscription.on_hold" -> handle_subscription_past_due(data)
      "subscription.plan_changed" -> handle_subscription_updated(data)
      "subscription.updated" -> handle_subscription_updated(data)
      "subscription.expired" -> handle_subscription_cancelled(data)
      _ ->
        Logger.debug("Ignoring Dodo webhook event: #{event_type}")
        {:error, :unhandled_event}
    end
  end

  # --- Private ---

  defp handle_subscription_activated(data) do
    sub_id = data["subscription_id"]
    customer_id = data["customer_id"] || data["customer"]
    metadata = data["metadata"] || %{}
    org_id = metadata["organization_id"]
    plan = metadata["plan"] || plan_for_product_id(data["product_id"])

    {:ok, %{
      provider: "dodo",
      provider_subscription_id: sub_id,
      provider_customer_id: customer_id,
      organization_id: org_id,
      plan: plan,
      status: "active"
    }}
  end

  defp handle_subscription_cancelled(data) do
    sub_id = data["subscription_id"]

    {:ok, %{
      provider: "dodo",
      provider_subscription_id: sub_id,
      status: "cancelled"
    }}
  end

  defp handle_subscription_past_due(data) do
    sub_id = data["subscription_id"]

    {:ok, %{
      provider: "dodo",
      provider_subscription_id: sub_id,
      status: "past_due"
    }}
  end

  defp handle_subscription_updated(data) do
    sub_id = data["subscription_id"]
    metadata = data["metadata"] || %{}
    plan = metadata["plan"] || plan_for_product_id(data["product_id"])

    {:ok, %{
      provider: "dodo",
      provider_subscription_id: sub_id,
      plan: plan,
      status: "active"
    }}
  end

  defp product_id_for_plan("pro", "annual", config), do: config[:product_id_pro_annual] || config[:product_id_pro]
  defp product_id_for_plan("team", "annual", config), do: config[:product_id_team_annual] || config[:product_id_team]
  defp product_id_for_plan("pro", _interval, config), do: config[:product_id_pro]
  defp product_id_for_plan("team", _interval, config), do: config[:product_id_team]

  defp plan_for_product_id(nil), do: "pro"

  defp plan_for_product_id(product_id) do
    config = dodo_config()

    cond do
      product_id == config[:product_id_pro] -> "pro"
      product_id == config[:product_id_pro_annual] -> "pro"
      product_id == config[:product_id_team] -> "team"
      product_id == config[:product_id_team_annual] -> "team"
      true ->
        Logger.warning("Unknown Dodo product_id #{inspect(product_id)}, falling back to pro")
        "pro"
    end
  end

  defp dodo_config do
    Application.get_env(:uptrack, :dodo) ||
      raise "Dodo Payments configuration not set"
  end
end
