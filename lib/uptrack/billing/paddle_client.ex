defmodule Uptrack.Billing.PaddleClient do
  @moduledoc """
  Behaviour for Paddle Billing API interactions.

  The real HTTP implementation lives in `PaddleClient.Http`.
  Tests can swap in a mock via `config :uptrack, :paddle_client`.
  """

  @callback create_transaction(params :: map()) :: {:ok, map()} | {:error, term()}
  @callback get_subscription(subscription_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(subscription_id :: String.t(), opts :: map()) :: {:ok, map()} | {:error, term()}

  def create_transaction(params), do: impl().create_transaction(params)
  def get_subscription(subscription_id), do: impl().get_subscription(subscription_id)
  def cancel_subscription(subscription_id, opts \\ %{}), do: impl().cancel_subscription(subscription_id, opts)

  defp impl, do: Application.get_env(:uptrack, :paddle_client, Uptrack.Billing.PaddleClient.Http)
end
