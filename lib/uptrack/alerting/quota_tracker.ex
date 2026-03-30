defmodule Uptrack.Alerting.QuotaTracker do
  @moduledoc """
  Tracks SMS/call alert usage per organization per month.

  Pure functions: `can_send?/2`, `remaining/2`, `current_month/0`.
  Impure functions: `get_or_create_quota/2`, `increment!/1`.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Alerting.SmsQuota
  alias Uptrack.Billing

  # --- Pure functions ---

  @doc "Returns the current month key (e.g., '2026-03')."
  def current_month do
    Date.utc_today() |> Calendar.strftime("%Y-%m")
  end

  @doc "Checks if the org can send another SMS/call based on used count and plan limit."
  def can_send?(used_count, plan) do
    limit = Billing.plan_limit(plan, :sms_alerts)
    limit == :unlimited or used_count < limit
  end

  @doc "Returns remaining quota."
  def remaining(used_count, plan) do
    limit = Billing.plan_limit(plan, :sms_alerts)
    if limit == :unlimited, do: :unlimited, else: max(limit - used_count, 0)
  end

  # --- Impure functions ---

  @doc "Gets or creates the quota record for the current month."
  def get_or_create_quota(organization_id, month \\ nil) do
    month = month || current_month()

    case AppRepo.get_by(SmsQuota, organization_id: organization_id, month: month) do
      nil ->
        %SmsQuota{}
        |> SmsQuota.changeset(%{organization_id: organization_id, month: month, used_count: 0})
        |> AppRepo.insert(on_conflict: :nothing, conflict_target: [:organization_id, :month])
        |> case do
          {:ok, quota} -> quota
          _ -> AppRepo.get_by!(SmsQuota, organization_id: organization_id, month: month)
        end

      quota ->
        quota
    end
  end

  @doc "Increments the used count by 1. Returns the updated quota."
  def increment!(quota) do
    {1, [updated]} =
      from(q in SmsQuota, where: q.id == ^quota.id, select: q)
      |> AppRepo.update_all(inc: [used_count: 1])

    updated
  end

  @doc """
  Checks quota and increments if allowed. Returns :ok or {:error, :quota_exhausted}.
  """
  def check_and_increment(organization_id, plan) do
    quota = get_or_create_quota(organization_id)

    if can_send?(quota.used_count, plan) do
      increment!(quota)
      :ok
    else
      {:error, :quota_exhausted}
    end
  end
end
