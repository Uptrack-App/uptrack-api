defmodule Uptrack.Billing.DodoClientMock do
  @moduledoc """
  Mock Dodo Payments client for tests. Returns canned responses.
  Test processes can configure responses via process dictionary.
  """

  @behaviour Uptrack.Billing.Dodo.DodoClient

  @impl true
  def create_subscription(_params) do
    case Process.get(:dodo_create_subscription) do
      nil ->
        {:ok, %{
          "subscription_id" => "sub_dodo_mock_#{System.unique_integer([:positive])}",
          "payment_link" => "https://test.checkout.dodopayments.com/mock",
          "payment_id" => "pay_mock_#{System.unique_integer([:positive])}"
        }}

      fun when is_function(fun) ->
        fun.()

      result ->
        result
    end
  end

  @impl true
  def get_subscription(_subscription_id) do
    case Process.get(:dodo_get_subscription) do
      nil -> {:ok, %{"subscription_id" => "sub_dodo_mock", "status" => "active"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def update_subscription(_subscription_id, _params) do
    case Process.get(:dodo_update_subscription) do
      nil -> {:ok, %{"subscription_id" => "sub_dodo_mock", "status" => "active"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def create_portal_session(_customer_id) do
    case Process.get(:dodo_create_portal_session) do
      nil -> {:ok, "https://test.customer.dodopayments.com/mock-portal"}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end
end
