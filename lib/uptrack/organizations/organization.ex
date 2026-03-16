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
    # Generate slug from name before calling changeset so validate_required passes
    attrs = maybe_add_slug_to_attrs(attrs)

    organization
    |> changeset(attrs)
  end

  @doc """
  Generates a URL-safe slug from an organization name.
  """
  def generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp maybe_add_slug_to_attrs(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    case Map.get(attrs, "slug") do
      nil ->
        name = Map.get(attrs, "name", "")
        Map.put(attrs, "slug", generate_slug(name))

      _ ->
        attrs
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9\-]*[a-z0-9]$/,
      message: "must be lowercase alphanumeric with hyphens, start and end with alphanumeric"
    )
    |> validate_length(:slug, min: 3, max: 50)
  end

  defp validate_plan(changeset) do
    valid_plans = ["free", "pro", "team"]
    validate_inclusion(changeset, :plan, valid_plans)
  end

end
