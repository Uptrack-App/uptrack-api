defmodule UptrackWeb.Api.AuthJSON do
  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization

  def user(%{user: user, organization: org}) do
    %{
      user: user_data(user),
      organization: organization_data(org)
    }
  end

  defp user_data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      provider: user.provider,
      role: user.role,
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
