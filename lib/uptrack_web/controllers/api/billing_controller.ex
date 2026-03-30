defmodule UptrackWeb.Api.BillingController do
  use UptrackWeb, :controller

  alias Uptrack.Billing

  require Logger

  @paid_plans Billing.paid_plans()

  @doc """
  Creates a checkout session via the configured payment provider.
  POST /api/billing/checkout

  Body: {"plan": "pro" | "team" | "business"}
  """
  def checkout(conn, %{"plan" => plan} = params) when plan in @paid_plans do
    org = conn.assigns.current_organization
    interval = params["interval"] || "monthly"

    case Billing.create_checkout_session(org, plan, interval) do
      {:ok, %{checkout_url: url, transaction_id: txn_id}} ->
        provider = provider_name()
        json(conn, %{checkout_url: url, transaction_id: txn_id, provider: provider})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{message: format_error(reason)}})
    end
  end

  def checkout(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{message: "Invalid plan. Must be one of: #{Enum.join(@paid_plans, ", ")}."}})
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
  Changes plan by directly updating the Paddle subscription (no checkout needed).
  POST /api/billing/change-plan

  Body: {"plan": "pro" | "team"}
  """
  def change_plan(conn, %{"plan" => plan}) when plan in @paid_plans do
    org = conn.assigns.current_organization

    case Billing.update_subscription_plan(org, plan) do
      {:ok, plan} ->
        json(conn, %{plan: plan})

      {:error, :no_active_subscription} ->
        conn
        |> put_status(422)
        |> json(%{error: %{message: "No active subscription found."}})

      {:error, reason} ->
        Logger.warning("change_plan: update failed for org #{org.id}: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: %{message: "Failed to change plan. Please try again."}})
    end
  end

  def change_plan(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{message: "Invalid plan. Must be one of: #{Enum.join(@paid_plans, ", ")}."}})
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

  @doc """
  Returns a preview of what would be paused if the user downgrades to Free.
  """
  def downgrade_preview(conn, _params) do
    organization = conn.assigns.current_organization
    free_limit = Billing.plan_limit("free", :monitors)
    excess = Uptrack.Monitoring.select_excess_monitors(organization.id, free_limit)

    json(conn, %{
      current_count: Uptrack.Monitoring.count_monitors(organization.id),
      limit: free_limit,
      monitors_to_pause: Enum.map(excess, fn m -> %{id: m.id, name: m.name, url: m.url} end)
    })
  end

  defp provider_name, do: Billing.payment_provider_name()

  defp format_error(%{body: %{"error" => %{"detail" => msg}}}), do: msg
  defp format_error(%{body: %{"message" => msg}}), do: msg
  defp format_error(%{body: body}) when is_binary(body), do: body
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
