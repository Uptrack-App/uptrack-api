defmodule Uptrack.Accounts.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @prefix "utk_"
  @key_length 32

  @schema_prefix "app"
  schema "api_keys" do
    field :name, :string
    field :key_prefix, :string
    field :key_hash, :string
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: ["read", "write"]
    field :is_active, :boolean, default: true

    # Virtual field - only populated at creation time
    field :raw_key, :string, virtual: true

    belongs_to :organization, Organization
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :expires_at, :scopes, :is_active, :organization_id, :created_by_id])
    |> validate_required([:name, :organization_id, :created_by_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_scopes()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:created_by_id)
  end

  def create_changeset(api_key, attrs) do
    raw_key = generate_key()
    key_prefix = String.slice(raw_key, 0, String.length(@prefix) + 8)

    api_key
    |> changeset(attrs)
    |> put_change(:raw_key, raw_key)
    |> put_change(:key_prefix, key_prefix)
    |> put_change(:key_hash, hash_key(raw_key))
  end

  def generate_key do
    random = :crypto.strong_rand_bytes(@key_length) |> Base.url_encode64(padding: false)
    @prefix <> random
  end

  def hash_key(raw_key) do
    :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
  end

  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp validate_scopes(changeset) do
    valid_scopes = ["read", "write", "admin"]

    case get_field(changeset, :scopes) do
      nil -> changeset
      scopes ->
        if Enum.all?(scopes, &(&1 in valid_scopes)) do
          changeset
        else
          add_error(changeset, :scopes, "contains invalid scope")
        end
    end
  end
end
