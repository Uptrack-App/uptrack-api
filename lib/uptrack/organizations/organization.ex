defmodule Uptrack.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Monitoring.{Monitor, AlertChannel, StatusPage, Incident}

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :plan, :string, default: "free"
    field :settings, :map, default: %{}

    has_many :users, User
    has_many :monitors, Monitor
    has_many :alert_channels, AlertChannel
    has_many :status_pages, StatusPage
    has_many :incidents, Incident

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :plan, :settings])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_slug()
    |> validate_plan()
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for creating a new organization.
  Generates slug from name if not provided.
  """
  def create_changeset(organization, attrs) do
    organization
    |> changeset(attrs)
    |> maybe_generate_slug()
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9\-]*[a-z0-9]$/,
      message: "must be lowercase alphanumeric with hyphens, start and end with alphanumeric"
    )
    |> validate_length(:slug, min: 3, max: 50)
  end

  defp validate_plan(changeset) do
    valid_plans = ["free", "starter", "pro", "enterprise"]
    validate_inclusion(changeset, :plan, valid_plans)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name)

        if name do
          slug =
            name
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9\s-]/, "")
            |> String.replace(~r/\s+/, "-")
            |> String.replace(~r/-+/, "-")
            |> String.trim("-")

          put_change(changeset, :slug, slug)
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
