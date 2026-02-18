defmodule UptrackWeb.Api.BillingController do
  use UptrackWeb, :controller

  alias Uptrack.Billing

  require Logger

  @doc """
  Creates a Paddle checkout transaction and returns the checkout URL.
  POST /api/billing/checkout

  Body: {"plan": "pro" | "team"}
  """
  def checkout(conn, %{"plan" => plan}) when plan in ["pro", "team"] do
    org = conn.assigns.current_organization

    case Billing.create_checkout_session(org, plan) do
      {:ok, %{checkout_url: url, transaction_id: txn_id}} ->
        json(conn, %{checkout_url: url, transaction_id: txn_id})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{message: format_error(reason)}})
    end
  end

  def checkout(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{message: "Invalid plan. Must be 'pro' or 'team'."}})
  end

  @doc """
  Returns the current subscription for the organization.
  GET /api/billing/subscription
  """
  def subscription(conn, _params) do
    org = conn.assigns.current_organization

    case Billing.get_active_subscription(org.id) do
      nil ->
        json(conn, %{data: nil, plan: org.plan})

      sub ->
        json(conn, %{
          data: %{
            id: sub.id,
            plan: sub.plan,
            status: sub.status,
            current_period_start: sub.current_period_start,
            current_period_end: sub.current_period_end,
            cancelled_at: sub.cancelled_at
          },
          plan: org.plan
        })
    end
  end

  @doc """
  Cancels the active subscription.
  POST /api/billing/cancel
  """
  def cancel(conn, _params) do
    org = conn.assigns.current_organization

    case Billing.cancel_active_subscription(org) do
      {:ok, _sub} ->
        json(conn, %{ok: true, message: "Subscription cancelled. You've been downgraded to the Free plan."})

      {:error, :no_active_subscription} ->
        conn
        |> put_status(404)
        |> json(%{error: %{message: "No active subscription to cancel."}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{message: format_error(reason)}})
    end
  end

  @doc """
  Changes plan by cancelling current subscription and creating a new checkout.
  POST /api/billing/change-plan

  Body: {"plan": "pro" | "team"}
  """
  def change_plan(conn, %{"plan" => plan}) when plan in ["pro", "team"] do
    org = conn.assigns.current_organization

    # Cancel existing subscription first — only proceed if cancel succeeds or no subscription exists
    cancel_result =
      case Billing.cancel_active_subscription(org) do
        {:ok, _} -> :ok
        {:error, :no_active_subscription} -> :ok
        {:error, reason} -> {:error, reason}
      end

    case cancel_result do
      :ok ->
        case Billing.create_checkout_session(org, plan) do
          {:ok, %{checkout_url: url, transaction_id: txn_id}} ->
            json(conn, %{checkout_url: url, transaction_id: txn_id})

          {:error, reason} ->
            conn
            |> put_status(422)
            |> json(%{error: %{message: format_error(reason)}})
        end

      {:error, reason} ->
        Logger.warning("change_plan: cancel failed for org #{org.id}: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: %{message: "Failed to cancel current subscription. Please try again."}})
    end
  end

  def change_plan(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{message: "Invalid plan. Must be 'pro' or 'team'."}})
  end

  @doc """
  Creates a Paddle customer portal session.
  POST /api/billing/portal
  """
  def portal(conn, _params) do
    org = conn.assigns.current_organization

    case Billing.create_portal_session(org) do
      {:ok, url} ->
        json(conn, %{portal_url: url})

      {:error, :no_active_subscription} ->
        conn
        |> put_status(404)
        |> json(%{error: %{message: "No active subscription."}})

      {:error, :no_customer_id} ->
        conn
        |> put_status(404)
        |> json(%{error: %{message: "No billing account found."}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{message: format_error(reason)}})
    end
  end

  defp format_error(%{body: %{"error" => %{"detail" => msg}}}), do: msg
  defp format_error(%{body: %{"message" => msg}}), do: msg
  defp format_error(%{body: body}) when is_binary(body), do: body
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
