defmodule UptrackWeb.Api.InvitationController do
  use UptrackWeb, :controller

  alias Uptrack.Teams
  alias Uptrack.Accounts.User

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Lists pending invitations for the organization.
  GET /api/organizations/:org_id/invitations
  """
  def index(conn, %{"organization_id" => org_id}) do
    with :ok <- authorize_manage(conn, org_id) do
      invitations = Teams.list_invitations(org_id)
      render(conn, :index, invitations: invitations)
    end
  end

  @doc """
  Creates a new invitation.
  POST /api/organizations/:org_id/invitations
  """
  def create(conn, %{"organization_id" => org_id, "email" => email, "role" => role}) do
    current_user = conn.assigns.current_user

    with :ok <- authorize_manage(conn, org_id),
         role_atom <- String.to_existing_atom(role),
         {:ok, invitation} <- Teams.invite_member(org_id, email, role_atom, current_user.id) do
      conn
      |> put_status(:created)
      |> render(:show, invitation: invitation)
    end
  end

  @doc """
  Cancels a pending invitation.
  DELETE /api/organizations/:org_id/invitations/:id
  """
  def delete(conn, %{"organization_id" => org_id, "id" => invitation_id}) do
    current_user = conn.assigns.current_user

    with :ok <- authorize_manage(conn, org_id),
         {:ok, _invitation} <- Teams.cancel_invitation(invitation_id, current_user.id) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Gets invitation details by token (public endpoint for accept flow).
  GET /api/invitations/:token
  """
  def show_by_token(conn, %{"token" => token}) do
    case Teams.get_invitation_by_token(token) do
      nil ->
        {:error, :not_found}

      invitation ->
        if Teams.TeamInvitation.expired?(invitation) do
          {:error, :invitation_expired}
        else
          render(conn, :show, invitation: invitation)
        end
    end
  end

  @doc """
  Accepts an invitation (for logged-in users).
  POST /api/invitations/:token/accept
  """
  def accept(conn, %{"token" => token}) do
    current_user = conn.assigns[:current_user]

    case Teams.accept_invitation(token, current_user) do
      {:ok, :needs_signup, invitation} ->
        # User needs to sign up first
        conn
        |> put_status(:accepted)
        |> render(:needs_signup, invitation: invitation)

      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> render(:accepted, user: user)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Authorization helpers

  defp authorize_manage(conn, org_id) do
    user = conn.assigns.current_user

    if user.organization_id == org_id and User.can_manage_team?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
