defmodule Uptrack.Auth.TotpCredential do
  @moduledoc """
  Schema for storing TOTP credentials.

  The secret is stored encrypted (binary). Backup codes are stored
  as a JSON array of `%{hash, used}` maps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "totp_credentials" do
    field :secret, :binary
    field :backup_codes, {:array, :map}, default: []
    field :enabled_at, :utc_datetime

    belongs_to :user, Uptrack.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:user_id, :secret, :backup_codes, :enabled_at])
    |> validate_required([:user_id, :secret])
    |> unique_constraint(:user_id)
  end
end
