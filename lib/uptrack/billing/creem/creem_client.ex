defmodule Uptrack.Billing.Creem.CreemClient do
  @moduledoc """
  Behaviour for Creem API interactions.

  The real HTTP implementation lives in `CreemClient.Http`.
  Tests can swap in a mock via `config :uptrack, :creem_client`.
  """

  @callback create_checkout(params :: map()) :: {:ok, map()} | {:error, term()}
  @callback get_subscription(subscription_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(subscription_id :: String.t(), mode :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback upgrade_subscription(subscription_id :: String.t(), params :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_billing_portal(customer_id :: String.t()) :: {:ok, map()} | {:error, term()}

  def create_checkout(params), do: impl().create_checkout(params)
  def get_subscription(subscription_id), do: impl().get_subscription(subscription_id)
  def cancel_subscription(subscription_id, mode \\ "immediate"), do: impl().cancel_subscription(subscription_id, mode)
  def upgrade_subscription(subscription_id, params), do: impl().upgrade_subscription(subscription_id, params)
  def create_billing_portal(customer_id), do: impl().create_billing_portal(customer_id)

  defp impl, do: Application.get_env(:uptrack, :creem_client, Uptrack.Billing.Creem.CreemClient.Http)
end
