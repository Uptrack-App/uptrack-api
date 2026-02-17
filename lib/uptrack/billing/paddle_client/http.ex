defmodule Uptrack.Billing.PaddleClient.Http do
  @moduledoc """
  Real HTTP implementation of the Paddle Billing API client.

  Uses Bearer token auth with a static API key (no token exchange needed).
  Paddle Billing API docs: https://developer.paddle.com/api-reference/overview
  """

  @behaviour Uptrack.Billing.PaddleClient

  require Logger

  # --- Public API (behaviour callbacks) ---

  @impl true
  def create_transaction(params) do
    post("/transactions", params)
  end

  @impl true
  def get_subscription(subscription_id) do
    get("/subscriptions/#{subscription_id}")
  end

  @impl true
  def cancel_subscription(subscription_id, opts) do
    body = Map.take(opts, [:effective_from])
    body = if map_size(body) == 0, do: %{effective_from: "next_billing_period"}, else: body

    post("/subscriptions/#{subscription_id}/cancel", body)
  end

  @impl true
  def create_portal_session(customer_id) do
    post("/customers/#{customer_id}/portal-sessions", %{})
  end

  # --- HTTP helpers ---

  defp get(path) do
    case Req.get(base_url() <> path,
           headers: auth_headers(),
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Paddle GET #{path} failed: status=#{status}")
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
      {:ok, %{status: status, body: %{"data" => data}}} when status in [200, 201] ->
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Paddle POST #{path} failed: status=#{status}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp auth_headers do
    config = paddle_config()

    [
      {"authorization", "Bearer #{config[:api_key]}"},
      {"content-type", "application/json"}
    ]
  end

  defp base_url, do: paddle_config()[:base_url]

  defp paddle_config do
    Application.get_env(:uptrack, :paddle) ||
      raise "Paddle configuration not set. Add PADDLE_API_KEY env var."
  end
end
