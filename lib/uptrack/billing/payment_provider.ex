defmodule Uptrack.Billing.PaymentProvider do
  @moduledoc """
  Behaviour for payment provider implementations.

  The active provider is configured via:

      config :uptrack, :payment_provider, Uptrack.Billing.Paddle.PaddleProvider

  All billing operations in the `Billing` context delegate to the configured provider.
  """

  @type checkout_result :: {:ok, %{checkout_url: String.t(), transaction_id: String.t()}}
  @type subscription_result :: {:ok, map()} | {:error, term()}

  @callback create_checkout(organization :: map(), plan :: String.t(), interval :: String.t()) ::
              checkout_result | {:error, term()}

  @callback cancel_subscription(subscription_id :: String.t()) ::
              subscription_result

  @callback update_subscription(subscription_id :: String.t(), plan :: String.t()) ::
              subscription_result

  @callback create_portal_session(customer_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback handle_webhook(event_type :: String.t(), data :: map()) ::
              :ok | {:ok, map()} | {:error, term()}
end
