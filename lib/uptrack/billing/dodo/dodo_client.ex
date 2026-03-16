defmodule Uptrack.Billing.Dodo.DodoClient do
  @moduledoc """
  Behaviour for Dodo Payments API interactions.

  The real HTTP implementation lives in `DodoClient.Http`.
  Tests can swap in a mock via `config :uptrack, :dodo_client`.
  """

  @callback create_subscription(params :: map()) :: {:ok, map()} | {:error, term()}
  @callback get_subscription(subscription_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback update_subscription(subscription_id :: String.t(), params :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_portal_session(customer_id :: String.t()) :: {:ok, map()} | {:error, term()}

  def create_subscription(params), do: impl().create_subscription(params)
  def get_subscription(subscription_id), do: impl().get_subscription(subscription_id)
  def update_subscription(subscription_id, params), do: impl().update_subscription(subscription_id, params)
  def create_portal_session(customer_id), do: impl().create_portal_session(customer_id)

  defp impl, do: Application.get_env(:uptrack, :dodo_client, Uptrack.Billing.Dodo.DodoClient.Http)
end
