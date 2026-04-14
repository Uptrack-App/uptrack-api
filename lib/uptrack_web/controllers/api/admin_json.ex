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
