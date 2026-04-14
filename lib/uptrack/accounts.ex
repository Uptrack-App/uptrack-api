defmodule Uptrack.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Ecto.Multi

  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    AppRepo.all(User)
  end

  @doc """
  Gets a resource owner by sub claim (required by Boruta OAuth).

  For org-scoped tokens, sub is "org:{id}" — returns the org as resource owner.
  """
  def get_by(sub: "org:" <> org_id) do
    case AppRepo.get(Organization, org_id) do
      nil -> {:error, "Organization not found"}
      org -> {:ok, %{sub: "org:#{org.id}", username: org.name}}
    end
  end

  def get_by(sub: _sub), do: {:error, "Unknown sub format"}

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: AppRepo.get!(User, id)
  def get_user(id), do: AppRepo.get(User, id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    AppRepo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("user@example.com")
      %User{}

      iex> get_user_by_email("nonexistent@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    AppRepo.get_by(User, email: email)
  end

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Registers a user with a new organization in a single transaction.

  Creates the organization first, then the user with the organization_id.
  The organization name is derived from the user's name or email.

  ## Examples

      iex> register_user_with_organization(%{name: "Jane Doe", email: "jane@example.com", password: "password123!"})
      {:ok, %User{organization_id: org_id}}

      iex> register_user_with_organization(%{email: "invalid"})
      {:error, :user, %Ecto.Changeset{}, %{}}

  """
  def register_user_with_organization(attrs) do
    org_name = derive_organization_name(attrs)
    slug = unique_org_slug(Organization.generate_slug(org_name))

    Multi.new()
    |> Multi.insert(:organization, Organization.create_changeset(%Organization{}, %{name: org_name, slug: slug}))
    |> Multi.insert(:user, fn %{organization: org} ->
      user_attrs = Map.put(attrs, "organization_id", org.id)

      %User{}
      |> User.registration_changeset(user_attrs)
    end)
    |> AppRepo.transaction()
    |> case do
      {:ok, %{user: user, organization: _org}} -> {:ok, user}
      {:error, :organization, changeset, _} -> {:error, :organization, changeset, %{}}
      {:error, :user, changeset, _} -> {:error, :user, changeset, %{}}
    end
  end

  @doc """
  Creates a user from OAuth data.

  ## Examples

      iex> create_user_from_oauth(%{field: value})
      {:ok, %User{}}

      iex> create_user_from_oauth(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_from_oauth(attrs) do
    %User{}
    |> User.oauth_changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Creates a user from OAuth data with a new organization in a single transaction.

  Creates the organization first, then the user with the organization_id.
  The organization name is derived from the user's name or email.

  ## Examples

      iex> create_user_from_oauth_with_organization(%{name: "Jane", email: "jane@example.com", provider: "github", provider_id: "123"})
      {:ok, %User{organization_id: org_id}}

      iex> create_user_from_oauth_with_organization(%{email: "invalid"})
      {:error, :user, %Ecto.Changeset{}, %{}}

  """
  def create_user_from_oauth_with_organization(attrs) do
    org_name = derive_organization_name(attrs)
    slug = unique_org_slug(Organization.generate_slug(org_name))

    Multi.new()
    |> Multi.insert(:organization, Organization.create_changeset(%Organization{}, %{name: org_name, slug: slug}))
    |> Multi.insert(:user, fn %{organization: org} ->
      user_attrs = Map.put(attrs, :organization_id, org.id)

      %User{}
      |> User.oauth_changeset(user_attrs)
    end)
    |> AppRepo.transaction()
    |> case do
      {:ok, %{user: user, organization: _org}} -> {:ok, user}
      {:error, :organization, changeset, _} -> {:error, :organization, changeset, %{}}
      {:error, :user, changeset, _} -> {:error, :user, changeset, %{}}
    end
  end

  # Appends a 4-char random hex suffix to guarantee slug uniqueness without a DB check.
  defp unique_org_slug(base_slug) do
    suffix = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
    base = if base_slug == "", do: "org", else: String.slice(base_slug, 0, 45)
    "#{base}-#{suffix}"
  end

  # Derives an organization name from user attributes
  defp derive_organization_name(attrs) do
    name = attrs["name"] || attrs[:name]
    email = attrs["email"] || attrs[:email]

    cond do
      name && String.trim(name) != "" ->
        "#{String.trim(name)}'s Organization"

      email ->
        username = email |> String.split("@") |> List.first()
        "#{username}'s Organization"

      true ->
        "My Organization"
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  @doc """
  Updates a user's notification preferences.

  ## Examples

      iex> update_user_preferences(user, %{notification_preferences: %{email_enabled: false}})
      {:ok, %User{}}

      iex> update_user_preferences(user, %{notification_preferences: invalid})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_preferences(%User{} = user, attrs) do
    user
    |> User.notification_preferences_changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification preference changes.

  ## Examples

      iex> change_user_preferences(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_preferences(%User{} = user, attrs \\ %{}) do
    User.notification_preferences_changeset(user, attrs)
  end

  @doc """
  Changes a user's password after verifying the current password.

  Returns `{:error, :invalid_password}` if the current password is wrong.
  """
  def change_password(%User{} = user, current_password, new_password) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(%{password: new_password})
      |> AppRepo.update()
    else
      {:error, :invalid_password}
    end
  end

  @doc """
  Deletes a user and their organization in a single transaction.

  For email/password users, requires password verification.
  For OAuth users, password can be nil (skips verification).
  """
  def delete_user_and_organization(%User{} = user, password) do
    # Verify password for email/password users
    if user.provider == nil && !User.valid_password?(user, password) do
      {:error, :invalid_password}
    else
      Multi.new()
      |> Multi.delete(:user, user)
      |> Multi.run(:organization, fn _repo, _changes ->
        org = Uptrack.Organizations.get_organization!(user.organization_id)
        AppRepo.delete(org)
      end)
      |> AppRepo.transaction()
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, _step, changeset, _} -> {:error, changeset}
      end
    end
  end

  # --- Magic Link Token Management ---

  alias Uptrack.Accounts.MagicLinkToken
  alias Uptrack.Auth.MagicLink

  @doc "Stores a hashed magic link token for an email."
  def store_magic_token(email, hashed_token) do
    %MagicLinkToken{}
    |> MagicLinkToken.changeset(%{
      email: String.downcase(email),
      hashed_token: hashed_token,
      expires_at: MagicLink.expires_at()
    })
    |> AppRepo.insert()
  end

  @doc "Finds an unexpired, unused token for an email and verifies the raw token."
  def verify_magic_token(email, raw_token) do
    hashed = MagicLink.hash_token(raw_token)

    query =
      from t in MagicLinkToken,
        where: t.email == ^String.downcase(email),
        where: t.hashed_token == ^hashed,
        where: is_nil(t.used_at),
        limit: 1

    case AppRepo.one(query) do
      nil ->
        {:error, :invalid_token}

      token ->
        cond do
          MagicLink.expired?(token) -> {:error, :token_expired}
          MagicLink.used?(token) -> {:error, :token_already_used}
          true -> {:ok, token}
        end
    end
  end

  @doc "Marks a token as used."
  def consume_magic_token(%MagicLinkToken{} = token) do
    token
    |> Ecto.Changeset.change(%{used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> AppRepo.update()
  end

  @doc """
  Finds an existing user by email, or creates a new user + organization.

  Used by magic link verification — the email is already verified by clicking the link.
  """
  def find_or_create_user_by_email(email) do
    email = String.downcase(email)

    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        name = MagicLink.name_from_email(email)

        create_user_from_oauth_with_organization(%{
          email: email,
          name: name,
          provider: "magic_link",
          provider_id: email
        })
    end
  end

  @doc "Deletes all expired tokens older than 24 hours."
  def cleanup_expired_magic_tokens do
    cutoff = DateTime.utc_now() |> DateTime.add(-86_400, :second)

    from(t in MagicLinkToken, where: t.expires_at < ^cutoff)
    |> AppRepo.delete_all()
  end
end
