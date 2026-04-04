defmodule Uptrack.Accounts.MagicLinkToken do
  @moduledoc "Schema for magic link authentication tokens."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @schema_prefix "app"

  schema "magic_link_tokens" do
    field :email, :string
    field :hashed_token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:email, :hashed_token, :expires_at])
    |> validate_required([:email, :hashed_token, :expires_at])
    |> validate_format(:email, ~r/@/)
  end
end
