defmodule Uptrack.Billing.CreemClientMock do
  @moduledoc """
  Mock Creem client for tests. Returns canned responses.
  Test processes can configure responses via process dictionary.
  """

  @behaviour Uptrack.Billing.Creem.CreemClient

  @impl true
  def create_checkout(_params) do
    case Process.get(:creem_create_checkout) do
      nil ->
        {:ok, %{
          "id" => "chk_creem_mock_#{System.unique_integer([:positive])}",
          "checkout_url" => "https://checkout.creem.io/mock"
        }}

      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def get_subscription(_subscription_id) do
    case Process.get(:creem_get_subscription) do
      nil -> {:ok, %{"id" => "sub_creem_mock", "status" => "active"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def cancel_subscription(_subscription_id, _mode) do
    case Process.get(:creem_cancel_subscription) do
      nil -> {:ok, %{"id" => "sub_creem_mock", "status" => "canceled"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def upgrade_subscription(_subscription_id, _params) do
    case Process.get(:creem_upgrade_subscription) do
      nil -> {:ok, %{"id" => "sub_creem_mock", "status" => "active"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end

  @impl true
  def create_billing_portal(_customer_id) do
    case Process.get(:creem_create_billing_portal) do
      nil -> {:ok, %{"portal_url" => "https://billing.creem.io/mock-portal"}}
      fun when is_function(fun) -> fun.()
      result -> result
    end
  end
end
