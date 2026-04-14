defmodule UptrackWeb.Api.AuthJSON do
  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization

  def user(%{user: user, organization: org} = assigns) do
    base = %{
      user: user_data(user),
      organization: organization_data(org)
    }

    case assigns[:impersonating_admin] do
      nil ->
        base

      admin ->
        started_at = assigns[:impersonation_started_at]

        expires_at =
          case started_at && DateTime.from_iso8601(started_at) do
            {:ok, dt, _} -> DateTime.add(dt, 3600, :second) |> DateTime.to_iso8601()
            _ -> nil
          end

        Map.merge(base, %{
          impersonating_admin: %{id: admin.id, name: admin.name, email: admin.email},
          impersonation_started_at: started_at,
          impersonation_expires_at: expires_at
        })
    end
  end

  defp user_data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      provider: user.provider,
      role: user.role,
      is_admin: user.is_admin,
      preferred_locale: user.preferred_locale,
      notification_preferences: user.notification_preferences,
      inserted_at: user.inserted_at
    }
  end

  defp organization_data(%Organization{} = org) do
    %{
      id: org.id,
      name: org.name,
      slug: org.slug,
      plan: org.plan
    }
  end
end
