defmodule Uptrack.Metrics.Retention do
  @moduledoc """
  Pure module for plan-based data retention limits.

  Maps plan names to retention durations and clamps query time ranges
  to enforce plan limits. No DB or external calls — purely functional.
  """

  alias Uptrack.Billing

  @doc """
  Returns the number of retention days for a given plan.

      iex> Retention.days_for_plan("free")
      180
      iex> Retention.days_for_plan("business")
      1825
  """
  def days_for_plan(plan) do
    Billing.plan_limit(plan, :retention_days) || 180
  end

  @doc """
  Clamps a time range to the plan's retention limit.

  Returns `{clamped_start, end_time}` where `clamped_start` is no earlier
  than `retention_days` before `end_time`.

      iex> Retention.clamp_range(very_old_start, now, "free")
      {six_months_ago, now}
  """
  def clamp_range(start_time, end_time, plan) do
    max_days = days_for_plan(plan)
    earliest_allowed = DateTime.add(end_time, -max_days * 86400, :second)

    clamped_start =
      if DateTime.compare(start_time, earliest_allowed) == :lt do
        earliest_allowed
      else
        start_time
      end

    {clamped_start, end_time}
  end

  @doc """
  Returns the appropriate VM query step for a given number of days.

  Shorter periods get finer granularity:
  - 1 day: 5-minute steps
  - 7 days: 1-hour steps
  - 30+ days: 1-day steps
  """
  def step_for_days(days) when days <= 1, do: "5m"
  def step_for_days(days) when days <= 7, do: "1h"
  def step_for_days(_days), do: "1d"
end
