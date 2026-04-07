defmodule Uptrack.Billing.AddOn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"

  @valid_types ~w(extra_monitors extra_fast_slots extra_teammates extra_subscribers)

  schema "add_ons" do
    field :type, :string
    field :quantity, :integer, default: 0

    belongs_to :organization, Uptrack.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def valid_types, do: @valid_types

  def changeset(add_on, attrs) do
    add_on
    |> cast(attrs, [:organization_id, :type, :quantity])
    |> validate_required([:organization_id, :type, :quantity])
    |> validate_inclusion(:type, @valid_types)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :type])
  end

  @doc "Returns price per unit in cents for each add-on type."
  def unit_price("extra_monitors"), do: 20        # $0.20/mo
  def unit_price("extra_fast_slots"), do: 100     # $1.00/mo
  def unit_price("extra_teammates"), do: 500      # $5.00/mo
  def unit_price("extra_subscribers"), do: 1      # $0.01/mo
  def unit_price(_), do: 0
end
