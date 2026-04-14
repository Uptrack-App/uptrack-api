defmodule UptrackWeb.Api.AdminJSON do
  alias Uptrack.Accounts.User

  def impersonation_started(%{target: target}) do
    %{
      ok: true,
      impersonating: user_summary(target)
    }
  end

  def impersonation_stopped(%{admin: admin}) do
    %{
      ok: true,
      user: user_summary(admin)
    }
  end

  def users(%{result: result}) do
    %{
      data: Enum.map(result.data, &user_row/1),
      page: result.page,
      per_page: result.per_page,
      total: result.total
    }
  end

  def organizations(%{result: result}) do
    %{
      data: Enum.map(result.data, &org_row/1),
      page: result.page,
      per_page: result.per_page,
      total: result.total
    }
  end

  defp user_summary(%User{} = user) do
    %{id: user.id, name: user.name, email: user.email, role: user.role}
  end

  defp user_summary(user) when is_map(user) do
    %{id: user.id, name: user.name, email: user.email, role: user.role}
  end

  defp user_row(row) do
    %{
      id: row.id,
      name: row.name,
      email: row.email,
      role: row.role,
      is_admin: row.is_admin,
      organization_id: row.organization_id,
      organization_name: row.organization_name,
      inserted_at: row.inserted_at
    }
  end

  # --- Notification Diagnostics ---

  def notification_health(%{stats: stats, latency: latency, daily_trend: daily_trend, per_org: per_org, error_breakdown: error_breakdown, last_success: last_success}) do
    channels =
      ~w(email slack discord telegram)
      |> Map.new(fn ct ->
        ct_stats = Map.get(stats, ct, %{})
        delivered = Map.get(ct_stats, "delivered", 0)
        failed = Map.get(ct_stats, "failed", 0)
        skipped = Map.get(ct_stats, "skipped", 0)
        total = delivered + failed + skipped

        {ct, %{
          delivered_7d: delivered,
          failed_7d: failed,
          skipped_7d: skipped,
          fail_rate_7d: if(total > 0, do: Float.round(failed / total, 4), else: 0.0),
          p95_duration_ms: Map.get(latency, ct, 0.0),
          last_success_at: Map.get(last_success, ct)
        }}
      end)

    %{
      channels: channels,
      daily_trend: daily_trend,
      error_breakdown: error_breakdown,
      per_org: Enum.map(per_org, fn item ->
        %{org_id: item.org_id, org_name: item[:org_name], delivered: item.delivered, failed: item.failed}
      end)
    }
  end

  def alert_channels(%{result: result}) do
    %{
      data: Enum.map(result.data, &channel_row/1),
      page: result.page,
      per_page: result.per_page,
      total: result.total
    }
  end

  def notification_deliveries(%{result: result}) do
    %{
      data: Enum.map(result.data, &delivery_row/1),
      page: result.page,
      per_page: result.per_page,
      total: result.total
    }
  end

  defp channel_row(row) do
    %{
      id: row.id,
      name: row.name,
      type: row.type,
      is_active: row.is_active,
      organization_id: row.organization_id,
      organization_name: row.organization_name,
      inserted_at: row.inserted_at
    }
  end

  defp delivery_row(row) do
    %{
      id: row.id,
      channel_type: row.channel_type,
      event_type: row.event_type,
      status: row.status,
      error_message: row.error_message,
      organization_name: row.organization_name,
      channel_name: row.channel_name,
      inserted_at: row.inserted_at
    }
  end

  defp org_row(row) do
    %{
      id: row.id,
      name: row.name,
      slug: row.slug,
      plan: row.plan,
      member_count: row.member_count,
      inserted_at: row.inserted_at
    }
  end
end
