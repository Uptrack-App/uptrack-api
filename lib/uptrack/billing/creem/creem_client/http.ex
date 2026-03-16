defmodule Uptrack.Billing.Creem.CreemClient.Http do
  @moduledoc """
  Real HTTP implementation of the Creem API client.

  Uses x-api-key header auth. Creem API docs: https://docs.creem.io/api-reference/
  """

  @behaviour Uptrack.Billing.Creem.CreemClient

  require Logger

  @impl true
  def create_checkout(params) do
    post("/v1/checkouts", params)
  end

  @impl true
  def get_subscription(subscription_id) do
    get("/v1/subscriptions?id=#{subscription_id}")
  end

  @impl true
  def cancel_subscription(subscription_id, mode) do
    post("/v1/subscriptions/#{subscription_id}/cancel", %{mode: mode})
  end

  @impl true
  def upgrade_subscription(subscription_id, params) do
    post("/v1/subscriptions/#{subscription_id}/upgrade", params)
  end

  @impl true
  def create_billing_portal(customer_id) do
    post("/v1/customers/billing", %{customer_id: customer_id})
  end

  # --- HTTP helpers ---

  defp get(path) do
    case Req.get(base_url() <> path,
           headers: auth_headers(),
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Creem GET #{path} failed: status=#{status} body=#{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp post(path, body) do
    case Req.post(base_url() <> path,
           headers: auth_headers(),
           json: body,
           retry: false
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Creem POST #{path} failed: status=#{status} body=#{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp auth_headers do
    config = creem_config()

    [
      {"x-api-key", config[:api_key]},
      {"content-type", "application/json"}
    ]
  end

  defp base_url, do: creem_config()[:base_url]

  defp creem_config do
    Application.get_env(:uptrack, :creem) ||
      raise "Creem configuration not set. Add CREEM_API_KEY env var."
  end
end
