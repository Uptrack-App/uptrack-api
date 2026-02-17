defmodule Uptrack.Billing.PaddleClientMock do
  @moduledoc """
  Mock Paddle client for tests. Returns canned responses.
  Test processes can configure responses via process dictionary.
  """

  @behaviour Uptrack.Billing.PaddleClient

  @impl true
  def create_transaction(_params) do
    case Process.get(:paddle_create_transaction) do
      nil ->
        {:ok, %{
          "id" => "txn_mock_#{System.unique_integer([:positive])}",
          "checkout" => %{"url" => "https://sandbox-checkout.paddle.com/mock"}
        }}

      fun when is_function(fun) ->
        fun.()

      result ->
        result
    end
  end

  @impl true
  def get_subscription(_subscription_id) do
    case Process.get(:paddle_get_subscription) do
      nil -> {:ok, %{"id" => "sub_mock", "status" => "active"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def cancel_subscription(_subscription_id, _opts) do
    case Process.get(:paddle_cancel_subscription) do
      nil -> {:ok, %{"id" => "sub_mock", "status" => "canceled"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def create_portal_session(_customer_id) do
    case Process.get(:paddle_create_portal_session) do
      nil ->
        {:ok, %{"urls" => %{"general" => %{"overview" => "https://sandbox-portal.paddle.com/mock"}}}}

      fun when is_function(fun) ->
        fun.()

      result ->
        result
    end
  end
end
