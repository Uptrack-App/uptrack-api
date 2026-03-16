defmodule Uptrack.Billing do
  @moduledoc """
  Billing context — manages subscriptions and payment provider checkout flow.

  Public API for the billing domain. Delegates to the configured PaymentProvider
  (Paddle, Dodo, or Creem) for checkout, cancellation, and portal operations.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Billing.Subscription
  alias Uptrack.Organizations
  alias Uptrack.Organizations.Organization

  require Logger

  @provider Application.compile_env(:uptrack, :payment_provider, Uptrack.Billing.Paddle.PaddleProvider)

  # --- Plan limits (pure data) ---

  @plan_limits %{
    "free" => %{monitors: 10, alert_channels: 2, status_pages: 1, team_members: 1, min_interval: 180, fast_monitors: 1},
    "pro" => %{monitors: 25, alert_channels: :unlimited, status_pages: 3, team_members: 5, min_interval: 30, fast_monitors: :unlimited},
    "team" => %{monitors: 150, alert_channels: :unlimited, status_pages: :unlimited, team_members: :unlimited, min_interval: 30, fast_monitors: :unlimited}
  }

  def plan_limits(plan), do: Map.get(@plan_limits, plan, @plan_limits["free"])

  def plan_limit(plan, resource), do: plan_limits(plan)[resource]

  def payment_provider, do: @provider

  def payment_provider_name do
    case to_string(@provider) do
      name when is_binary(name) ->
        cond do
          String.contains?(name, "Dodo") -> "dodo"
          String.contains?(name, "Creem") -> "creem"
          true -> "paddle"
        end
    end
  end

  # --- Plan enforcement ---

  @doc """
  Checks if the organization can create a new resource of the given type.
  Returns :ok or {:error, message}.
  """
  def check_plan_limit(%Organization{} = org, resource) when resource in [:monitors, :alert_channels, :status_pages, :team_members] do
    limit = plan_limit(org.plan, resource)

    if limit == :unlimited do
      :ok
    else
      current_count = count_resource(org.id, resource)

      if current_count < limit do
        :ok
      else
        {:error, "You've reached the #{resource_label(resource)} limit for the #{String.capitalize(org.plan)} plan (#{limit}). Upgrade for more."}
      end
    end
  end

  @doc """
  Checks if the requested check interval meets the plan minimum.
  Returns :ok or {:error, message}.
  """
  def check_interval_limit(%Organization{} = org, interval) when is_integer(interval) do
    min = plan_limit(org.plan, :min_interval)

    cond do
      interval >= min ->
        :ok

      # Below plan minimum — check if fast monitor slot is available (only for intervals ≥ 30s)
      interval >= 30 ->
        fast_limit = plan_limit(org.plan, :fast_monitors)

        cond do
          fast_limit == :unlimited ->
            :ok

          is_integer(fast_limit) and Uptrack.Monitoring.count_fast_monitors(org.id) < fast_limit ->
            :ok

          true ->
            {:error, "Free plan includes 1 Fast Monitor (30s). You've used yours — upgrade to Pro for unlimited 30s monitors."}
        end

      true ->
        {:error, "The minimum supported check interval is 30 seconds."}
    end
  end

  defp count_resource(org_id, :monitors), do: Uptrack.Monitoring.count_monitors(org_id)
  defp count_resource(org_id, :alert_channels), do: Uptrack.Monitoring.count_alert_channels(org_id)
  defp count_resource(org_id, :status_pages), do: Uptrack.Monitoring.count_status_pages(org_id)
  defp count_resource(org_id, :team_members), do: Uptrack.Teams.count_members(org_id)

  defp resource_label(:monitors), do: "monitor"
  defp resource_label(:alert_channels), do: "alert channel"
  defp resource_label(:status_pages), do: "status page"
  defp resource_label(:team_members), do: "team member"

  # --- Subscription queries ---

  def get_active_subscription(organization_id) do
    from(s in Subscription,
      where: s.organization_id == ^organization_id,
      where: s.status in ["active", "trialing"],
      order_by: [desc: s.inserted_at],
      limit: 1
    )
    |> AppRepo.one()
  end

  def get_subscription_by_paddle_id(paddle_subscription_id) do
    AppRepo.get_by(Subscription, paddle_subscription_id: paddle_subscription_id)
  end

  def get_subscription_by_provider_id(provider_subscription_id) do
    AppRepo.get_by(Subscription, provider_subscription_id: provider_subscription_id)
  end

  @doc "Find subscription by either legacy paddle_subscription_id or generic provider_subscription_id."
  def find_subscription(subscription_id) do
    get_subscription_by_provider_id(subscription_id) ||
      get_subscription_by_paddle_id(subscription_id)
  end

  # --- Checkout flow (delegates to configured provider) ---

  @doc """
  Creates a checkout session via the configured payment provider.
  Returns {:ok, %{checkout_url, transaction_id}} or {:error, reason}.
  """
  def create_checkout_session(organization, plan, interval \\ "monthly")

  def create_checkout_session(%Organization{} = organization, plan, interval)
      when plan in ["pro", "team"] and interval in ["monthly", "annual"] do
    @provider.create_checkout(organization, plan, interval)
  end

  def create_checkout_session(_organization, _plan, _interval), do: {:error, :invalid_plan}

  @doc """
  Creates a customer portal session for managing billing.
  Returns {:ok, url} or {:error, reason}.
  """
  def create_portal_session(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        customer_id = subscription.provider_customer_id || subscription.paddle_customer_id

        if is_nil(customer_id) do
          {:error, :no_customer_id}
        else
          @provider.create_portal_session(customer_id)
        end
    end
  end

  # --- Subscription management ---

  @doc """
  Switches an active subscription from one paid plan to another.
  Returns {:ok, plan} on success or {:error, reason} on failure.
  """
  def update_subscription_plan(%Organization{} = organization, plan) when plan in ["pro", "team"] do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        sub_id = subscription.provider_subscription_id || subscription.paddle_subscription_id

        case @provider.update_subscription(sub_id, plan) do
          {:ok, _} ->
            subscription
            |> Subscription.changeset(%{plan: plan})
            |> AppRepo.update()
            |> case do
              {:ok, _} ->
                update_organization_plan(organization.id, plan)
                {:ok, plan}

              {:error, _} = err ->
                err
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def update_subscription_plan(_organization, _plan), do: {:error, :invalid_plan}

  def cancel_active_subscription(%Organization{} = organization) do
    case get_active_subscription(organization.id) do
      nil ->
        {:error, :no_active_subscription}

      subscription ->
        sub_id = subscription.provider_subscription_id || subscription.paddle_subscription_id

        with {:ok, _} <- @provider.cancel_subscription(sub_id) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          subscription
          |> Subscription.changeset(%{status: "cancelled", cancelled_at: now})
          |> AppRepo.update()
          |> tap(fn
            {:ok, _} -> update_organization_plan(organization.id, "free")
            _ -> :ok
          end)
        end
    end
  end

  # --- Dodo webhook handler (called from WebhookController) ---

  @doc """
  Handles a Dodo webhook event. The DodoProvider.handle_webhook/2 returns
  normalized data that this function uses to create/update subscriptions.
  """
  def handle_dodo_webhook(event_type, data) do
    alias Uptrack.Billing.Dodo.DodoProvider

    case DodoProvider.handle_webhook(event_type, data) do
      {:ok, %{status: "cancelled", provider_subscription_id: sub_id}} ->
        case get_subscription_by_provider_id(sub_id) do
          nil ->
            Logger.warning("Dodo webhook: #{event_type} for unknown subscription #{sub_id}")
            :ok

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

      {:ok, %{status: "past_due", provider_subscription_id: sub_id}} ->
        case get_subscription_by_provider_id(sub_id) do
          nil ->
            Logger.warning("Dodo webhook: #{event_type} for unknown subscription #{sub_id}")
            :ok

          subscription ->
            subscription
            |> Subscription.changeset(%{status: "past_due"})
            |> AppRepo.update()
        end

      {:ok, %{status: "active"} = attrs} ->
        handle_dodo_subscription_active(attrs)

      {:error, :unhandled_event} ->
        :ok

      {:error, reason} ->
        Logger.error("Dodo webhook error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_dodo_subscription_active(attrs) do
    sub_id = attrs[:provider_subscription_id]

    case get_subscription_by_provider_id(sub_id) do
      nil ->
        org_id = attrs[:organization_id]

        if is_nil(org_id) do
          Logger.error("Dodo webhook: subscription.active without organization_id in metadata")
          {:error, :missing_organization_id}
        else
          %Subscription{}
          |> Subscription.changeset(%{
            organization_id: org_id,
            provider: "dodo",
            provider_subscription_id: sub_id,
            provider_customer_id: attrs[:provider_customer_id],
            plan: attrs[:plan] || "pro",
            status: "active"
          })
          |> AppRepo.insert()
          |> tap(fn
            {:ok, sub} -> update_organization_plan(sub.organization_id, sub.plan)
            _ -> :ok
          end)
        end

      existing ->
        existing
        |> Subscription.changeset(%{
          plan: attrs[:plan] || existing.plan,
          status: "active",
          cancelled_at: nil
        })
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} ->
            if sub.plan != existing.plan do
              update_organization_plan(sub.organization_id, sub.plan)
            end
          _ -> :ok
        end)
    end
  end

  # --- Creem webhook handler (called from WebhookController) ---

  @doc """
  Handles a Creem webhook event. The CreemProvider.handle_webhook/2 returns
  normalized data that this function uses to create/update subscriptions.
  """
  def handle_creem_webhook(event_type, data) do
    alias Uptrack.Billing.Creem.CreemProvider

    case CreemProvider.handle_webhook(event_type, data) do
      {:ok, %{status: "cancelled", provider_subscription_id: sub_id}} ->
        case get_subscription_by_provider_id(sub_id) do
          nil ->
            Logger.warning("Creem webhook: #{event_type} for unknown subscription #{sub_id}")
            :ok

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

      {:ok, %{status: "past_due", provider_subscription_id: sub_id}} ->
        case get_subscription_by_provider_id(sub_id) do
          nil ->
            Logger.warning("Creem webhook: #{event_type} for unknown subscription #{sub_id}")
            :ok

          subscription ->
            subscription
            |> Subscription.changeset(%{status: "past_due"})
            |> AppRepo.update()
        end

      {:ok, %{status: "active"} = attrs} ->
        handle_creem_subscription_active(attrs)

      {:error, :unhandled_event} ->
        :ok

      {:error, reason} ->
        Logger.error("Creem webhook error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_creem_subscription_active(attrs) do
    sub_id = attrs[:provider_subscription_id]

    case get_subscription_by_provider_id(sub_id) do
      nil ->
        org_id = attrs[:organization_id]

        if is_nil(org_id) do
          Logger.error("Creem webhook: subscription.active without organization_id in metadata")
          {:error, :missing_organization_id}
        else
          %Subscription{}
          |> Subscription.changeset(%{
            organization_id: org_id,
            provider: "creem",
            provider_subscription_id: sub_id,
            provider_customer_id: attrs[:provider_customer_id],
            plan: attrs[:plan] || "pro",
            status: "active",
            current_period_start: attrs[:current_period_start],
            current_period_end: attrs[:current_period_end]
          })
          |> AppRepo.insert()
          |> tap(fn
            {:ok, sub} -> update_organization_plan(sub.organization_id, sub.plan)
            _ -> :ok
          end)
        end

      existing ->
        existing
        |> Subscription.changeset(%{
          plan: attrs[:plan] || existing.plan,
          status: "active",
          cancelled_at: nil,
          current_period_start: attrs[:current_period_start],
          current_period_end: attrs[:current_period_end]
        })
        |> AppRepo.update()
        |> tap(fn
          {:ok, sub} ->
            if sub.plan != existing.plan do
              update_organization_plan(sub.organization_id, sub.plan)
            end
          _ -> :ok
        end)
    end
  end

  # --- Paddle webhook handlers (kept for backward compatibility) ---

  @doc false
  def handle_paddle_webhook(event_type, data) do
    handle_webhook_event(event_type, data)
  end

  def handle_webhook_event("subscription.created", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.activated", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.trialing", data) do
    handle_subscription_activated(data)
  end

  def handle_webhook_event("subscription.canceled", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.canceled for unknown subscription #{data["id"]}")
        :ok

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

  def handle_webhook_event("subscription.updated", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.updated for unknown subscription #{data["id"]}")
        :ok

      subscription ->
        {period_start, period_end} = parse_billing_period(data["current_billing_period"])
        status = normalize_status(data["status"])

        price_id =
          case data["items"] do
            [%{"price" => %{"id" => pid}} | _] -> pid
            _ -> nil
          end

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

  def handle_webhook_event("subscription.past_due", data) do
    case get_subscription_by_paddle_id(data["id"]) do
      nil ->
        Logger.warning("Webhook: subscription.past_due for unknown subscription #{data["id"]}")
        :ok

      subscription ->
        subscription
        |> Subscription.changeset(%{status: "past_due"})
        |> AppRepo.update()
    end
  end

  def handle_webhook_event("transaction.payment_failed", data) do
    sub_id = data["subscription_id"]

    if sub_id do
      case get_subscription_by_paddle_id(sub_id) do
        nil -> :ok
        subscription ->
          subscription
          |> Subscription.changeset(%{status: "past_due"})
          |> AppRepo.update()
      end
    else
      :ok
    end
  end

  def handle_webhook_event(event_name, _data) do
    Logger.debug("Ignoring Paddle webhook event: #{event_name}")
    :ok
  end

  # --- Private helpers ---

  defp handle_subscription_activated(data) do
    paddle_sub_id = data["id"]
    customer_id = data["customer_id"]
    custom_data = data["custom_data"] || %{}
    org_id = custom_data["organization_id"]
    status = normalize_status(data["status"])

    price_id =
      case data["items"] do
        [%{"price" => %{"id" => pid}} | _] -> pid
        _ -> nil
      end

    plan = plan_for_price_id(price_id)
    {period_start, period_end} = parse_billing_period(data["current_billing_period"])

    case get_subscription_by_paddle_id(paddle_sub_id) do
      nil ->
        if is_nil(org_id) do
          Logger.error("Webhook: subscription.activated without organization_id in custom_data")
          {:error, :missing_organization_id}
        else
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
          |> AppRepo.insert()
          |> tap(fn
            {:ok, sub} -> update_organization_plan(sub.organization_id, plan)
            _ -> :ok
          end)
        end

      existing ->
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
  end

  defp update_organization_plan(organization_id, plan) do
    case Organizations.get_organization(organization_id) do
      nil ->
        Logger.error("Cannot update plan: organization #{organization_id} not found")

      org ->
        org
        |> Organization.changeset(%{plan: plan})
        |> AppRepo.update()
    end
  end

  defp plan_for_price_id(nil) do
    Logger.warning("Paddle webhook received nil price_id, falling back to pro plan")
    "pro"
  end

  defp plan_for_price_id(price_id) do
    config = paddle_config()

    cond do
      price_id == config[:price_id_pro] -> "pro"
      price_id == config[:price_id_team] -> "team"
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

  defp paddle_config do
    Application.get_env(:uptrack, :paddle) ||
      raise "Paddle configuration not set"
  end
end
