defmodule Uptrack.Emails.CustomSender do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "custom_senders" do
    field :sender_name, :string
    field :sender_email, :string
    field :verified, :boolean, default: false
    field :verification_token, :string

    belongs_to :organization, Uptrack.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(sender, attrs) do
    sender
    |> cast(attrs, [:organization_id, :sender_name, :sender_email, :verified, :verification_token])
    |> validate_required([:organization_id, :sender_name, :sender_email])
    |> validate_format(:sender_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:organization_id)
    |> unique_constraint(:verification_token)
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
