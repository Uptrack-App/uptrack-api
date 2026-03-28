defmodule Uptrack.Billing.Paddle.PaddleProvider do
  @moduledoc """
  Paddle implementation of the PaymentProvider behaviour.

  Wraps the existing PaddleClient to conform to the generic provider contract.
  """

  @behaviour Uptrack.Billing.PaymentProvider

  alias Uptrack.Billing.PaddleClient

  require Logger

  @impl true
  def create_checkout(organization, plan, interval \\ "monthly")

  def create_checkout(organization, plan, interval) when plan in ["pro", "team"] do
    config = paddle_config()
    price_id = price_id_for_plan(plan, interval, config)

    success_url = Application.get_env(:uptrack, :frontend_url, "https://uptrack.app")
    checkout_settings = %{url: "#{success_url}/dashboard/settings?billing=success"}

    case PaddleClient.create_transaction(%{
           items: [%{price_id: price_id, quantity: 1}],
           custom_data: %{
             organization_id: organization.id,
             plan: plan
           },
           checkout: %{url: checkout_settings.url}
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

  def create_checkout(_organization, _plan, _interval), do: {:error, :invalid_plan}

  @impl true
  def cancel_subscription(subscription_id) do
    PaddleClient.cancel_subscription(subscription_id, %{effective_from: "immediately"})
  end

  @impl true
  def update_subscription(subscription_id, plan) when plan in ["pro", "team"] do
    config = paddle_config()
    price_id = price_id_for_plan(plan, "monthly", config)

    PaddleClient.update_subscription(subscription_id, %{
      items: [%{price_id: price_id, quantity: 1}],
      proration_billing_mode: "prorated_immediately"
    })
  end

  def update_subscription(_subscription_id, _plan), do: {:error, :invalid_plan}

  @impl true
  def create_portal_session(customer_id) do
    case PaddleClient.create_portal_session(customer_id) do
      {:ok, %{"urls" => %{"general" => %{"overview" => url}}}} ->
        {:ok, url}

      {:ok, data} ->
        url = get_in(data, ["urls", "general", "overview"]) || data["id"]
        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_webhook(event_type, data) do
    # Paddle webhook handling remains in Billing context for backward compatibility.
    # This callback delegates back to Billing.handle_webhook_event/2.
    Uptrack.Billing.handle_paddle_webhook(event_type, data)
  end

  defp price_id_for_plan("pro", "annual", config), do: config[:price_id_pro_annual] || config[:price_id_pro]
  defp price_id_for_plan("team", "annual", config), do: config[:price_id_team_annual] || config[:price_id_team]
  defp price_id_for_plan("pro", _interval, config), do: config[:price_id_pro]
  defp price_id_for_plan("team", _interval, config), do: config[:price_id_team]

  defp paddle_config do
    Application.get_env(:uptrack, :paddle) ||
      raise "Paddle configuration not set"
  end
end
