defmodule UptrackWeb.Api.TeamController do
  use UptrackWeb, :controller

  alias Uptrack.Teams
  alias Uptrack.Accounts.User

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Lists all members of the current organization.
  GET /api/organizations/:org_id/members
  """
  def index(conn, %{"organization_id" => org_id}) do
    with :ok <- authorize_view(conn, org_id) do
      members = Teams.list_members(org_id)
      render(conn, :index, members: members)
    end
  end

  @doc """
  Updates a member's role.
  PATCH /api/organizations/:org_id/members/:user_id
  """
  def update(conn, %{"organization_id" => org_id, "user_id" => user_id, "role" => role}) do
    current_user = conn.assigns.current_user

    with :ok <- authorize_manage(conn, org_id),
         role_atom <- String.to_existing_atom(role),
         {:ok, member} <- Teams.update_member_role(org_id, user_id, role_atom, current_user.id) do
      render(conn, :show, member: member)
    end
  end

  @doc """
  Removes a member from the organization.
  DELETE /api/organizations/:org_id/members/:user_id
  """
  def delete(conn, %{"organization_id" => org_id, "user_id" => user_id}) do
    current_user = conn.assigns.current_user

    with :ok <- authorize_manage(conn, org_id),
         {:ok, _member} <- Teams.remove_member(org_id, user_id, current_user.id) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Transfers ownership to another member.
  POST /api/organizations/:org_id/transfer-ownership
  """
  def transfer_ownership(conn, %{"organization_id" => org_id, "to_user_id" => to_user_id}) do
    current_user = conn.assigns.current_user

    with :ok <- authorize_owner(conn, org_id),
         {:ok, new_owner} <- Teams.transfer_ownership(org_id, current_user.id, to_user_id) do
      render(conn, :show, member: new_owner)
    end
  end

  # Authorization helpers

  defp authorize_view(conn, org_id) do
    user = conn.assigns.current_user

    if user.organization_id == org_id and User.can_access_dashboard?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_manage(conn, org_id) do
    user = conn.assigns.current_user

    if user.organization_id == org_id and User.can_manage_team?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_owner(conn, org_id) do
    user = conn.assigns.current_user

    if user.organization_id == org_id and User.is_owner?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
