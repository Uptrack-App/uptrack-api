defmodule Uptrack.Monitoring.StatusPage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{StatusPageMonitor}

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "status_pages" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :is_public, :boolean, default: true
    field :custom_domain, :string
    field :logo_url, :string
    field :theme_config, :map, default: %{}

    # Password protection fields
    field :password_protected, :boolean, default: false
    field :password_hash, :string
    field :password, :string, virtual: true

    # Email subscription settings
    field :allow_subscriptions, :boolean, default: false

    # Multi-language support
    field :default_language, :string, default: "en"

    belongs_to :organization, Organization
    belongs_to :user, User
    has_many :status_page_monitors, StatusPageMonitor, on_delete: :delete_all
    has_many :monitors, through: [:status_page_monitors, :monitor]

    timestamps()
  end

  @doc false
  def changeset(status_page, attrs) do
    status_page
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :is_public,
      :custom_domain,
      :logo_url,
      :theme_config,
      :password_protected,
      :password,
      :allow_subscriptions,
      :default_language,
      :organization_id,
      :user_id
    ])
    |> validate_required([:name, :slug, :organization_id, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/i,
      message: "must contain only letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug)
    |> validate_url(:custom_domain)
    |> validate_url(:logo_url)
    |> maybe_generate_slug()
    |> maybe_hash_password()
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Verifies a password against the stored hash.
  Returns true if the password matches, false otherwise.
  """
  def verify_password(%__MODULE__{password_hash: nil}, _password), do: false
  def verify_password(%__MODULE__{password_hash: hash}, password) do
    Bcrypt.verify_pass(password, hash)
  end

  @doc """
  Checks if password is required for access.
  """
  def requires_password?(%__MODULE__{password_protected: true, password_hash: hash})
      when not is_nil(hash), do: true
  def requires_password?(_), do: false

  defp maybe_hash_password(changeset) do
    password = get_change(changeset, :password)
    password_protected = get_field(changeset, :password_protected)

    cond do
      # If password protection is being disabled, clear the hash
      password_protected == false ->
        put_change(changeset, :password_hash, nil)

      # If a new password is provided and protection is enabled, hash it
      password && password_protected ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      true ->
        changeset
    end
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, slugify(name))
        end

      _ ->
        changeset
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case url do
        nil ->
          []

        "" ->
          []

        url when is_binary(url) ->
          uri = URI.parse(url)

          if uri.scheme in ["http", "https"] and uri.host do
            []
          else
            [{field, "must be a valid URL"}]
          end

        _ ->
          [{field, "must be a valid URL"}]
      end
    end)
  end
end
