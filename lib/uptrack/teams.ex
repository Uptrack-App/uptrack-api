defmodule Uptrack.Teams do
  @moduledoc """
  The Teams context handles team membership, invitations, and audit logging.

  This module provides functions for:
  - Managing team members and their roles
  - Sending and accepting invitations
  - Transferring organization ownership
  - Recording audit log entries
  """

  import Ecto.Query, warn: false
  require Logger

  alias Uptrack.AppRepo
  alias Uptrack.Accounts
  alias Uptrack.Accounts.User
  alias Uptrack.Organizations
  alias Uptrack.Teams.{TeamInvitation, AuditLog}
  alias Uptrack.Emails.InvitationEmail
  alias Uptrack.Mailer

  # ============================================================================
  # Team Members
  # ============================================================================

  def count_members(organization_id) do
    User
    |> where([u], u.organization_id == ^organization_id)
    |> AppRepo.aggregate(:count)
  end

  def count_members_by_role(organization_id, role) do
    User
    |> where([u], u.organization_id == ^organization_id and u.role == ^role)
    |> AppRepo.aggregate(:count)
  end

  @doc """
  Lists all members of an organization with their roles.
  """
  def list_members(organization_id) do
    User
    |> where([u], u.organization_id == ^organization_id)
    |> order_by([u], [asc: :role, asc: :name])
    |> AppRepo.all()
  end

  @doc """
  Gets a specific member by user_id within an organization.
  """
  def get_member(organization_id, user_id) do
    User
    |> where([u], u.organization_id == ^organization_id and u.id == ^user_id)
    |> AppRepo.one()
  end

  @doc """
  Updates a member's role within an organization.
  Returns error if trying to change the last owner's role.
  """
  def update_member_role(organization_id, user_id, new_role, actor_user_id) do
    with {:ok, member} <- fetch_member(organization_id, user_id),
         :ok <- validate_role_change(organization_id, member, new_role),
         {:ok, updated} <- do_update_role(member, new_role) do
      log_action(organization_id, actor_user_id, "team.member_role_changed", "user", user_id,
        metadata: %{
          "old_role" => to_string(member.role),
          "new_role" => to_string(new_role),
          "member_email" => member.email
        }
      )

      {:ok, updated}
    end
  end

  defp fetch_member(organization_id, user_id) do
    case get_member(organization_id, user_id) do
      nil -> {:error, :member_not_found}
      member -> {:ok, member}
    end
  end

  defp validate_role_change(organization_id, member, new_role) do
    if member.role == :owner and new_role != :owner do
      # Check if there are other owners
      owner_count = count_owners(organization_id)

      if owner_count <= 1 do
        {:error, :cannot_remove_last_owner}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp do_update_role(member, new_role) do
    member
    |> User.changeset(%{role: new_role})
    |> AppRepo.update()
  end

  defp count_owners(organization_id) do
    User
    |> where([u], u.organization_id == ^organization_id and u.role == :owner)
    |> AppRepo.aggregate(:count)
  end

  @doc """
  Removes a member from an organization.
  Cannot remove the last owner.
  """
  def remove_member(organization_id, user_id, actor_user_id) do
    with {:ok, member} <- fetch_member(organization_id, user_id),
         :ok <- validate_can_remove(organization_id, member) do
      case AppRepo.delete(member) do
        {:ok, deleted} ->
          log_action(organization_id, actor_user_id, "team.member_removed", "user", user_id,
            metadata: %{"member_email" => deleted.email, "member_role" => to_string(deleted.role)}
          )

          {:ok, deleted}

        error ->
          error
      end
    end
  end

  defp validate_can_remove(organization_id, member) do
    if member.role == :owner and count_owners(organization_id) <= 1 do
      {:error, :cannot_remove_last_owner}
    else
      :ok
    end
  end

  @doc """
  Transfers ownership from one user to another.
  The current owner becomes an admin, and the target becomes the owner.
  """
  def transfer_ownership(organization_id, from_user_id, to_user_id) do
    AppRepo.transaction(fn ->
      with {:ok, from_user} <- fetch_member(organization_id, from_user_id),
           {:ok, to_user} <- fetch_member(organization_id, to_user_id),
           :ok <- validate_is_owner(from_user),
           {:ok, _} <- do_update_role(from_user, :admin),
           {:ok, new_owner} <- do_update_role(to_user, :owner) do
        log_action(
          organization_id,
          from_user_id,
          "team.ownership_transferred",
          "organization",
          organization_id,
          metadata: %{
            "from_user_id" => from_user_id,
            "from_email" => from_user.email,
            "to_user_id" => to_user_id,
            "to_email" => to_user.email
          }
        )

        new_owner
      else
        {:error, reason} -> AppRepo.rollback(reason)
      end
    end)
  end

  defp validate_is_owner(user) do
    if user.role == :owner, do: :ok, else: {:error, :not_owner}
  end

  # ============================================================================
  # Invitations
  # ============================================================================

  @doc """
  Lists pending invitations for an organization.
  """
  def list_invitations(organization_id) do
    TeamInvitation
    |> where([i], i.organization_id == ^organization_id)
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> order_by([i], desc: :inserted_at)
    |> preload(:invited_by)
    |> AppRepo.all()
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(token) do
    TeamInvitation
    |> where([i], i.token == ^token)
    |> preload([:organization, :invited_by])
    |> AppRepo.one()
  end

  @doc """
  Creates a new invitation and sends the invitation email.
  """
  def invite_member(organization_id, email, role, invited_by_user_id) do
    # Check if user is already a member
    existing_user =
      User
      |> where([u], u.email == ^String.downcase(email) and u.organization_id == ^organization_id)
      |> AppRepo.one()

    if existing_user do
      {:error, :already_member}
    else
      attrs = %{
        email: email,
        role: role,
        organization_id: organization_id,
        invited_by_id: invited_by_user_id
      }

      case create_invitation(attrs) do
        {:ok, invitation} ->
          log_action(organization_id, invited_by_user_id, "team.invitation_sent", "invitation",
            invitation.id,
            metadata: %{"email" => email, "role" => to_string(role)}
          )

          send_invitation_email(invitation, organization_id, invited_by_user_id)

          {:ok, invitation}

        error ->
          error
      end
    end
  end

  defp create_invitation(attrs) do
    %TeamInvitation{}
    |> TeamInvitation.changeset(attrs)
    |> AppRepo.insert()
  end

  defp send_invitation_email(invitation, organization_id, invited_by_user_id) do
    org = Organizations.get_organization!(organization_id)
    inviter = Accounts.get_user!(invited_by_user_id)
    locale = inviter.preferred_locale || "en"

    invitation
    |> InvitationEmail.invitation_email(org.name, inviter.name, locale)
    |> Mailer.deliver()
  rescue
    e ->
      Logger.error("Failed to send invitation email to #{invitation.email}: #{inspect(e)}")
  end

  @doc """
  Cancels a pending invitation.
  """
  def cancel_invitation(invitation_id, actor_user_id) do
    case AppRepo.get(TeamInvitation, invitation_id) do
      nil ->
        {:error, :not_found}

      invitation ->
        case AppRepo.delete(invitation) do
          {:ok, deleted} ->
            log_action(
              invitation.organization_id,
              actor_user_id,
              "team.invitation_cancelled",
              "invitation",
              invitation_id,
              metadata: %{"email" => deleted.email}
            )

            {:ok, deleted}

          error ->
            error
        end
    end
  end

  @doc """
  Accepts an invitation by token.
  If the user exists, adds them to the organization.
  If not, returns the invitation for the signup flow.
  """
  def accept_invitation(token, user_or_nil \\ nil) do
    with {:ok, invitation} <- fetch_valid_invitation(token) do
      case user_or_nil do
        nil ->
          # Return invitation for signup flow
          {:ok, :needs_signup, invitation}

        user ->
          # Add existing user to organization
          add_user_to_organization(invitation, user)
      end
    end
  end

  defp fetch_valid_invitation(token) do
    case get_invitation_by_token(token) do
      nil ->
        {:error, :invitation_not_found}

      invitation ->
        if TeamInvitation.expired?(invitation) do
          {:error, :invitation_expired}
        else
          {:ok, invitation}
        end
    end
  end

  defp add_user_to_organization(invitation, user) do
    AppRepo.transaction(fn ->
      # Update user's organization and role
      case user
           |> User.changeset(%{organization_id: invitation.organization_id, role: invitation.role})
           |> AppRepo.update() do
        {:ok, updated_user} ->
          # Delete the invitation
          AppRepo.delete!(invitation)

          log_action(
            invitation.organization_id,
            updated_user.id,
            "team.invitation_accepted",
            "user",
            updated_user.id,
            metadata: %{"email" => updated_user.email, "role" => to_string(invitation.role)}
          )

          updated_user

        {:error, reason} ->
          AppRepo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates a new user from an invitation (signup flow).
  """
  def accept_invitation_with_signup(token, user_attrs) do
    with {:ok, invitation} <- fetch_valid_invitation(token) do
      # Merge invitation data with user attrs
      full_attrs =
        Map.merge(user_attrs, %{
          organization_id: invitation.organization_id,
          role: invitation.role
        })

      AppRepo.transaction(fn ->
        case Accounts.create_user(full_attrs) do
          {:ok, user} ->
            AppRepo.delete!(invitation)

            log_action(
              invitation.organization_id,
              user.id,
              "team.member_added",
              "user",
              user.id,
              metadata: %{
                "email" => user.email,
                "role" => to_string(invitation.role),
                "via" => "invitation"
              }
            )

            user

          {:error, reason} ->
            AppRepo.rollback(reason)
        end
      end)
    end
  end

  # ============================================================================
  # Audit Logging
  # ============================================================================

  @doc """
  Creates an audit log entry from a Plug.Conn.

  Extracts user_id, organization_id, and ip_address from conn assigns.
  Automatically enriches metadata with `impersonated_by` when impersonation
  is active (conn.assigns.impersonating_admin is present).
  """
  def log_action_from_conn(conn, action, resource_type, resource_id \\ nil, opts \\ []) do
    user = conn.assigns[:current_user]
    org = conn.assigns[:current_organization]

    base_metadata = Keyword.get(opts, :metadata, %{})

    metadata =
      case conn.assigns[:impersonating_admin] do
        nil -> base_metadata
        admin -> Map.put(base_metadata, :impersonated_by, admin.id)
      end

    ip_address =
      case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
        [header | _] -> header |> String.split(",") |> List.first() |> String.trim()
        [] -> to_string(:inet.ntoa(conn.remote_ip))
      end

    log_action(
      org && org.id,
      user && user.id,
      action,
      resource_type,
      resource_id,
      Keyword.merge(opts, metadata: metadata, ip_address: ip_address)
    )
  end

  @doc """
  Creates an audit log entry.
  """
  def log_action(organization_id, user_id, action, resource_type, resource_id \\ nil, opts \\ []) do
    attrs = %{
      organization_id: organization_id,
      user_id: user_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: Keyword.get(opts, :metadata, %{}),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> AppRepo.insert()
  rescue
    error ->
      Logger.error("Failed to write audit log: #{inspect(error)}")
      {:error, :audit_log_failed}
  end

  @doc """
  Lists audit logs for an organization with optional filters.
  """
  def list_audit_logs(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    action_filter = Keyword.get(opts, :action)
    user_filter = Keyword.get(opts, :user_id)
    since = Keyword.get(opts, :since)

    query =
      AuditLog
      |> where([a], a.organization_id == ^organization_id)
      |> order_by([a], desc: :created_at)
      |> limit(^limit)
      |> offset(^offset)

    query = apply_action_filter(query, action_filter)
    query = apply_user_filter(query, user_filter)
    query = apply_since_filter(query, since)

    query
    |> preload(:user)
    |> AppRepo.all()
  end

  @doc """
  Counts audit logs for an organization.
  """
  def count_audit_logs(organization_id, opts \\ []) do
    action_filter = Keyword.get(opts, :action)
    user_filter = Keyword.get(opts, :user_id)
    since = Keyword.get(opts, :since)

    query =
      AuditLog
      |> where([a], a.organization_id == ^organization_id)

    query = apply_action_filter(query, action_filter)
    query = apply_user_filter(query, user_filter)
    query = apply_since_filter(query, since)

    AppRepo.aggregate(query, :count)
  end

  # Supports both exact match ("team.member_added") and prefix match ("team.")
  defp apply_action_filter(query, nil), do: query

  defp apply_action_filter(query, filter) do
    if String.ends_with?(filter, ".") do
      prefix = filter <> "%"
      where(query, [a], like(a.action, ^prefix))
    else
      where(query, [a], a.action == ^filter)
    end
  end

  defp apply_user_filter(query, nil), do: query
  defp apply_user_filter(query, user_id), do: where(query, [a], a.user_id == ^user_id)

  defp apply_since_filter(query, nil), do: query
  defp apply_since_filter(query, %DateTime{} = since), do: where(query, [a], a.created_at >= ^since)
end
