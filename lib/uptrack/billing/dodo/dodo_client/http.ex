defmodule Uptrack.Billing.Dodo.DodoClient.Http do
  @moduledoc """
  Real HTTP implementation of the Dodo Payments API client.

  Uses Bearer token auth. Dodo API docs: https://docs.dodopayments.com/api-reference/
  """

  @behaviour Uptrack.Billing.Dodo.DodoClient

  require Logger

  @impl true
  def create_subscription(params) do
    post("/subscriptions", params)
  end

  @impl true
  def get_subscription(subscription_id) do
    get("/subscriptions/#{subscription_id}")
  end

  @impl true
  def update_subscription(subscription_id, params) do
    patch("/subscriptions/#{subscription_id}", params)
  end

  @impl true
  def create_portal_session(customer_id) do
    config = dodo_config()
    business_id = config[:business_id]
    base = config[:base_url]

    # Dodo customer portal: GET /customers/{customer_id}/customer-portal/session
    case Req.get("#{base}/customers/#{customer_id}/customer-portal/session",
           headers: auth_headers(),
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"link" => url}}} ->
        {:ok, url}

      {:ok, %{status: 200, body: body}} ->
        # Fallback: construct static portal URL
        {:ok, body["link"] || "#{portal_base_url(config)}/login/#{business_id}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Dodo portal session failed: status=#{status} body=#{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
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
        Logger.error("Dodo GET #{path} failed: status=#{status} body=#{inspect(body)}")
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
        Logger.error("Dodo POST #{path} failed: status=#{status} body=#{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp patch(path, body) do
    case Req.patch(base_url() <> path,
           headers: auth_headers(),
           json: body,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Dodo PATCH #{path} failed: status=#{status} body=#{inspect(body)}")
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp auth_headers do
    config = dodo_config()

    [
      {"authorization", "Bearer #{config[:api_key]}"},
      {"content-type", "application/json"}
    ]
  end

  defp base_url, do: dodo_config()[:base_url]

  defp portal_base_url(config) do
    if String.contains?(config[:base_url] || "", "test") do
      "https://test.customer.dodopayments.com"
    else
      "https://customer.dodopayments.com"
    end
  end

  defp dodo_config do
    Application.get_env(:uptrack, :dodo) ||
      raise "Dodo Payments configuration not set. Add DODO_API_KEY env var."
  end
end
