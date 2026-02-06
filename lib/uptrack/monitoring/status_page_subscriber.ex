defmodule Uptrack.Monitoring.StatusPageSubscriber do
  @moduledoc """
  Schema for status page email subscribers.

  Subscribers receive email notifications when incidents are created or resolved
  for monitors on the status page they're subscribed to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Monitoring.StatusPage

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "status_page_subscribers" do
    field :email, :string
    field :verified, :boolean, default: false
    field :verification_token, :string
    field :verification_sent_at, :utc_datetime
    field :unsubscribe_token, :string
    field :subscribed_at, :utc_datetime

    belongs_to :status_page, StatusPage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [:email, :status_page_id, :verified, :subscribed_at])
    |> validate_required([:email, :status_page_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
    |> unique_constraint([:status_page_id, :email], message: "already subscribed to this status page")
    |> generate_tokens()
    |> foreign_key_constraint(:status_page_id)
  end

  @doc """
  Marks the subscriber as verified.
  """
  def verify_changeset(subscriber) do
    subscriber
    |> change(%{
      verified: true,
      verification_token: nil,
      subscribed_at: DateTime.utc_now()
    })
  end

  defp generate_tokens(changeset) do
    if get_field(changeset, :verification_token) do
      changeset
    else
      changeset
      |> put_change(:verification_token, generate_token())
      |> put_change(:unsubscribe_token, generate_token())
      |> put_change(:verification_sent_at, DateTime.utc_now())
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
