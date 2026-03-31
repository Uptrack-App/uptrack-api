defmodule Uptrack.Billing.Webhooks do
  @moduledoc """
  Paddle webhook event handlers.

  Processes subscription lifecycle events from Paddle and updates
  local subscription records and organization plans accordingly.
  """

  alias Uptrack.AppRepo
  alias Uptrack.Billing
  alias Uptrack.Billing.Subscription
  alias Uptrack.Organizations

  require Logger

  # --- Public API ---

  def handle_event("subscription.created", data), do: handle_activated(data)
  def handle_event("subscription.activated", data), do: handle_activated(data)
  def handle_event("subscription.trialing", data), do: handle_activated(data)

  def handle_event("subscription.canceled", data) do
    case Billing.find_subscription(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.canceled for unknown subscription #{data["id"]}")
        :ok

      %{status: "cancelled"} = subscription ->
        {:ok, subscription}

      subscription ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        subscription
        |> Subscription.changeset(%{status: "cancelled", cancelled_at: now})
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} -> update_organization_plan(sub.organization_id, "free")
          _ -> :ok
        end)
    end
  end

  def handle_event("subscription.updated", data) do
    case Billing.find_subscription(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.updated for unknown subscription #{data["id"]}")
        :ok

      subscription ->
        {period_start, period_end} = parse_billing_period(data["current_billing_period"])
        status = normalize_status(data["status"])
        price_id = extract_price_id(data)
        plan = if price_id, do: plan_for_price_id(price_id), else: subscription.plan

        subscription
        |> Subscription.changeset(%{
          plan: plan,
          status: status,
          current_period_start: period_start,
          current_period_end: period_end
        })
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} ->
            if sub.plan != subscription.plan do
              update_organization_plan(sub.organization_id, sub.plan)
            end
          _ -> :ok
        end)
    end
  end

  def handle_event("subscription.past_due", data) do
    case Billing.find_subscription(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.past_due for unknown subscription #{data["id"]}")
        :ok

      %{status: "past_due"} = subscription ->
        {:ok, subscription}

      subscription ->
        subscription
        |> Subscription.changeset(%{status: "past_due"})
        |> AppRepo.update()
    end
  end

  def handle_event("transaction.payment_failed", data) do
    sub_id = data["subscription_id"]

    if sub_id do
      case Billing.get_subscription_by_paddle_id(sub_id) do
        nil -> :ok
        %{status: "past_due"} = subscription -> {:ok, subscription}
        subscription ->
          subscription
          |> Subscription.changeset(%{status: "past_due"})
          |> AppRepo.update()
      end
    else
      :ok
    end
  end

  def handle_event(event_name, _data) do
    Logger.debug("Ignoring Paddle webhook event: #{event_name}")
    :ok
  end

  # --- Private helpers ---

  defp handle_activated(data) do
    paddle_sub_id = data["id"]
    customer_id = data["customer_id"]
    custom_data = data["custom_data"] || %{}
    org_id = custom_data["organization_id"]
    status = normalize_status(data["status"])
    price_id = extract_price_id(data)
    plan = plan_for_price_id(price_id)
    {period_start, period_end} = parse_billing_period(data["current_billing_period"])

    case Billing.get_subscription_by_paddle_id(paddle_sub_id) do
      nil ->
        create_subscription(paddle_sub_id, customer_id, org_id, plan, status, period_start, period_end)

      existing ->
        reactivate_subscription(existing, plan, status, period_start, period_end)
    end
  end

  defp create_subscription(_paddle_sub_id, _customer_id, nil, _plan, _status, _start, _end) do
    Logger.error("Webhook: subscription.activated without organization_id in custom_data")
    {:error, :missing_organization_id}
  end

  defp create_subscription(paddle_sub_id, customer_id, org_id, plan, status, period_start, period_end) do
    result =
      %Subscription{}
      |> Subscription.changeset(%{
        organization_id: org_id,
        paddle_subscription_id: paddle_sub_id,
        paddle_customer_id: customer_id,
        provider: "paddle",
        plan: plan,
        status: status,
        current_period_start: period_start,
        current_period_end: period_end
      })
      |> AppRepo.insert(
        on_conflict: :nothing,
        conflict_target: :paddle_subscription_id
      )

    case result do
      {:ok, %{id: nil}} ->
        :ok

      {:ok, sub} ->
        update_organization_plan(sub.organization_id, plan)
        {:ok, sub}

      error ->
        error
    end
  end

  defp reactivate_subscription(existing, plan, status, period_start, period_end) do
    existing
    |> Subscription.changeset(%{
      plan: plan,
      status: status,
      current_period_start: period_start,
      current_period_end: period_end,
      cancelled_at: nil
    })
    |> AppRepo.update()
    |> tap(fn
      {:ok, sub} -> update_organization_plan(sub.organization_id, plan)
      _ -> :ok
    end)
  end

  @doc false
  def update_organization_plan(organization_id, plan) do
    with %{} = org <- Organizations.get_organization(organization_id),
         {:ok, _} <- org |> Uptrack.Organizations.Organization.changeset(%{plan: plan}) |> AppRepo.update() do
      enforce_plan_limits(organization_id, plan)
    else
      nil -> Logger.error("Cannot update plan: organization #{organization_id} not found")
      err -> err
    end
  end

  defp enforce_plan_limits(organization_id, plan) do
    monitor_limit = Uptrack.Billing.Plans.plan_limit(plan, :monitors)

    if is_integer(monitor_limit) do
      excess = Uptrack.Monitoring.select_excess_monitors(organization_id, monitor_limit)

      if excess != [] do
        ids = Enum.map(excess, & &1.id)
        count = Uptrack.Monitoring.pause_monitors(ids)
        Logger.info("Paused #{count} monitors for org #{organization_id} after downgrade to #{plan}")
      end
    end
  end

  defp extract_price_id(data) do
    case data["items"] do
      [%{"price" => %{"id" => pid}} | _] -> pid
      _ -> nil
    end
  end

  defp plan_for_price_id(nil) do
    Logger.warning("Paddle webhook received nil price_id, falling back to pro plan")
    "pro"
  end

  defp plan_for_price_id(price_id) do
    config = Application.get_env(:uptrack, :paddle) || raise "Paddle configuration not set"

    cond do
      price_id == config[:price_id_pro] -> "pro"
      price_id == config[:price_id_pro_annual] -> "pro"
      price_id == config[:price_id_team] -> "team"
      price_id == config[:price_id_team_annual] -> "team"
      price_id == config[:price_id_business] -> "business"
      price_id == config[:price_id_business_annual] -> "business"
      true ->
        Logger.warning("Unknown Paddle price_id #{inspect(price_id)}, falling back to pro plan")
        "pro"
    end
  end

  defp normalize_status("trialing"), do: "trialing"
  defp normalize_status(_), do: "active"

  defp parse_billing_period(nil), do: {nil, nil}

  defp parse_billing_period(%{"starts_at" => starts_at, "ends_at" => ends_at}) do
    {parse_timestamp(starts_at), parse_timestamp(ends_at)}
  end

  defp parse_billing_period(_), do: {nil, nil}

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
