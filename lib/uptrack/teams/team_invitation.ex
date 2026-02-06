defmodule Uptrack.Teams.TeamInvitation do
  @moduledoc """
  Schema for team member invitations.

  Invitations are sent via email and contain a unique token.
  They expire after 7 days by default.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Accounts.User

  @roles ~w(admin editor viewer notify_only)a
  @token_bytes 32
  @expiration_days 7

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"

  schema "team_invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: @roles, default: :editor
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :organization, Organization
    belongs_to :invited_by, User, foreign_key: :invited_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid roles for invitations.
  Note: :owner is not included as ownership must be transferred, not invited.
  """
  def roles, do: @roles

  @doc """
  Creates a changeset for a new invitation.
  Automatically generates token and sets expiration.
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :organization_id, :invited_by_id])
    |> validate_required([:email, :role, :organization_id])
    |> validate_email()
    |> validate_inclusion(:role, @roles)
    |> put_token()
    |> put_expiration()
    |> unique_constraint([:organization_id, :email],
      message: "has already been invited to this organization"
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
  end

  defp put_token(changeset) do
    if get_field(changeset, :token) do
      changeset
    else
      token = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)
      put_change(changeset, :token, token)
    end
  end

  defp put_expiration(changeset) do
    if get_field(changeset, :expires_at) do
      changeset
    else
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(@expiration_days, :day)
        |> DateTime.truncate(:second)

      put_change(changeset, :expires_at, expires_at)
    end
  end

  @doc """
  Returns true if the invitation has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
