defmodule UptrackWeb.Api.InvitationJSON do
  @moduledoc """
  JSON views for invitation endpoints.
  """

  alias Uptrack.Teams.TeamInvitation

  def index(%{invitations: invitations}) do
    %{data: for(invitation <- invitations, do: invitation_data(invitation))}
  end

  def show(%{invitation: invitation}) do
    %{data: invitation_data(invitation)}
  end

  def needs_signup(%{invitation: invitation}) do
    %{
      status: "needs_signup",
      data: %{
        email: invitation.email,
        role: invitation.role,
        organization: %{
          id: invitation.organization.id,
          name: invitation.organization.name
        },
        expires_at: invitation.expires_at
      }
    }
  end

  def accepted(%{user: user}) do
    %{
      status: "accepted",
      data: %{
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        organization_id: user.organization_id
      }
    }
  end

  defp invitation_data(%TeamInvitation{} = invitation) do
    %{
      id: invitation.id,
      email: invitation.email,
      role: invitation.role,
      expires_at: invitation.expires_at,
      invited_at: invitation.inserted_at,
      invited_by:
        if Ecto.assoc_loaded?(invitation.invited_by) and invitation.invited_by do
          %{
            id: invitation.invited_by.id,
            name: invitation.invited_by.name,
            email: invitation.invited_by.email
          }
        end,
      organization:
        if Ecto.assoc_loaded?(invitation.organization) and invitation.organization do
          %{
            id: invitation.organization.id,
            name: invitation.organization.name
          }
        end
    }
  end
end
