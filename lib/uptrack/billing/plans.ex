defmodule Uptrack.Billing.Plans do
  @moduledoc """
  Pure plan data and enforcement logic — no database calls.

  Contains plan limits, feature gating, channel type restrictions,
  and interval/slot validation. All functions are pure and testable
  without a database.
  """

  alias Uptrack.Organizations.Organization

  # --- Plan limits (pure data) ---

  @plan_limits %{
    "free" => %{
      monitors: 20, alert_channels: 3, status_pages: 5, team_members: 2,
      min_interval: 30, fast_monitors: 10, quick_monitors: :unlimited, webhooks_per_monitor: 1,
      regions: 3, retention_days: 30, sms_alerts: 0, subscribers: 100,
      notify_only_seats: 0
    },
    "pro" => %{
      monitors: 30, alert_channels: 5, status_pages: 5, team_members: 3,
      min_interval: 30, fast_monitors: :unlimited, quick_monitors: :unlimited, webhooks_per_monitor: 2,
      regions: 5, retention_days: 730, sms_alerts: 30, subscribers: 1_000,
      notify_only_seats: 1
    },
    "team" => %{
      monitors: 60, alert_channels: :unlimited, status_pages: :unlimited, team_members: 5,
      min_interval: 30, fast_monitors: :unlimited, quick_monitors: :unlimited, webhooks_per_monitor: 5,
      regions: 15, retention_days: 730, sms_alerts: 100, subscribers: 5_000,
      notify_only_seats: 3
    },
    "business" => %{
      monitors: 625, alert_channels: :unlimited, status_pages: :unlimited, team_members: 15,
      min_interval: 30, fast_monitors: :unlimited, quick_monitors: :unlimited, webhooks_per_monitor: 10,
      regions: 15, retention_days: 1825, sms_alerts: 200, subscribers: 10_000,
      notify_only_seats: 5
    }
  }

  @all_plans Map.keys(@plan_limits)
  @paid_plans @all_plans -- ["free"]

  def all_plans, do: @all_plans
  def paid_plans, do: @paid_plans

  def plan_limits(plan), do: Map.get(@plan_limits, plan, @plan_limits["free"])

  def plan_limit(plan, resource), do: plan_limits(plan)[resource]

  # --- Feature gating ---

  @business_features ~w(whitelabel custom_email_sender sso rbac priority_support)a
  @team_features ~w(status_page_customization custom_domain password_protection
                     incident_updates maintenance_scheduling search_engine_optout
                     weekly_reports mattermost)a

  @doc """
  Checks if the organization's plan includes a specific feature.
  Returns true or false.
  """
  def can_use_feature?(%Organization{plan: plan}, feature) when feature in @business_features do
    plan == "business"
  end

  def can_use_feature?(%Organization{plan: plan}, feature) when feature in @team_features do
    plan in ["team", "business"]
  end

  def can_use_feature?(_org, _feature), do: true

  @doc """
  Returns the list of allowed alert channel types for a plan.
  """
  def allowed_channel_types("free"), do: ["email", "slack", "discord"]
  def allowed_channel_types("pro"), do: ["email", "slack", "ms_teams", "discord", "telegram", "webhook"]
  def allowed_channel_types(_plan), do: :all

  # --- Plan enforcement (pure — callers provide counts) ---

  @doc """
  Checks if a requested region count is within the plan limit.
  Returns :ok or {:error, message}.
  """
  def check_region_limit(%Organization{} = org, region_count) when is_integer(region_count) do
    limit = plan_limit(org.plan, :regions)

    if region_count <= limit do
      :ok
    else
      {:error, "Your #{String.capitalize(org.plan)} plan supports up to #{limit} monitoring regions. Upgrade for more."}
    end
  end

  @doc """
  Checks if the requested check interval meets the plan minimum.
  For slots (fast/quick monitors), pass the current counts.
  Returns :ok or {:error, message}.
  """
  def check_interval_limit(%Organization{} = org, interval, slot_counts \\ %{})
      when is_integer(interval) do
    min = plan_limit(org.plan, :min_interval)

    cond do
      interval >= min ->
        :ok

      interval >= 120 ->
        check_slot_limit(
          plan_limit(org.plan, :fast_monitors),
          Map.get(slot_counts, :fast_monitors, 0),
          "Fast Monitor",
          "2-min"
        )

      interval >= 60 ->
        check_slot_limit(
          plan_limit(org.plan, :quick_monitors),
          Map.get(slot_counts, :quick_monitors, 0),
          "Quick Monitor",
          "1-min"
        )

      interval >= 30 and min <= 30 ->
        :ok

      interval >= 30 ->
        {:error, "30-second checks are available on Pro plans and above. Upgrade for faster monitoring."}

      true ->
        {:error, "The minimum supported check interval is 30 seconds."}
    end
  end

  defp check_slot_limit(:unlimited, _current, _label, _interval_label), do: :ok

  defp check_slot_limit(limit, current, label, interval_label) when is_integer(limit) do
    if current < limit do
      :ok
    else
      {:error, "Your plan includes #{limit} #{label} slot(s) (#{interval_label}). You've used yours — upgrade for more."}
    end
  end

  @doc """
  Maps a resource atom to its add-on type string.
  Returns nil for resources without add-ons.
  """
  def resource_to_add_on(:monitors), do: "extra_monitors"
  def resource_to_add_on(:fast_monitors), do: "extra_fast_slots"
  def resource_to_add_on(:team_members), do: "extra_teammates"
  def resource_to_add_on(:subscribers), do: "extra_subscribers"
  def resource_to_add_on(_), do: nil
end
