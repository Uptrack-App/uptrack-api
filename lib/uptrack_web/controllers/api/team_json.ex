defmodule UptrackWeb.Api.TeamJSON do
  @moduledoc """
  JSON views for team member endpoints.
  """

  alias Uptrack.Accounts.User

  def index(%{members: members}) do
    %{data: for(member <- members, do: member_data(member))}
  end

  def show(%{member: member}) do
    %{data: member_data(member)}
  end

  defp member_data(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      joined_at: user.inserted_at,
      can_manage_team: User.can_manage_team?(user),
      can_edit: User.can_edit?(user),
      is_owner: User.is_owner?(user)
    }
  end
end
