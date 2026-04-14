defmodule Uptrack.Teams.AuditLog do
  @moduledoc """
  Schema for audit log entries.

  Audit logs are immutable records of significant actions taken within an organization.
  They are used for security, compliance, and debugging purposes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Accounts.User

  # Common action types
  @actions ~w(
    organization.created
    organization.updated
    organization.deleted
    team.invitation_sent
    team.invitation_cancelled
    team.invitation_accepted
    team.member_added
    team.member_removed
    team.member_role_changed
    team.ownership_transferred
    monitor.created
    monitor.updated
    monitor.deleted
    monitor.paused
    monitor.resumed
    alert_channel.created
    alert_channel.updated
    alert_channel.deleted
    alert_channel.tested
    status_page.created
    status_page.updated
    status_page.deleted
    incident.created
    incident.updated
    incident.resolved
    incident.acknowledged
    user.logged_in
    user.logged_out
    user.settings_updated
    admin.impersonation_started
    admin.impersonation_ended
    admin.impersonation_expired
    admin.notification_tested
  )

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, Uniq.UUID
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string
    field :created_at, :utc_datetime

    belongs_to :organization, Organization
    belongs_to :user, User
  end

  @doc """
  Returns the list of known action types.
  """
  def actions, do: @actions

  @doc """
  Creates a changeset for a new audit log entry.
  """
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :action,
      :resource_type,
      :resource_id,
      :metadata,
      :ip_address,
      :user_agent,
      :organization_id,
      :user_id
    ])
    |> validate_required([:action, :resource_type, :organization_id])
    |> put_created_at()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
  end

  defp put_created_at(changeset) do
    if get_field(changeset, :created_at) do
      changeset
    else
      put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end

  @doc """
  Creates a log entry struct from action details.
  Helper for building audit log entries in contexts.
  """
  def build(organization_id, user_id, action, resource_type, resource_id \\ nil, opts \\ []) do
    %__MODULE__{
      organization_id: organization_id,
      user_id: user_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: Keyword.get(opts, :metadata, %{}),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent),
      created_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
