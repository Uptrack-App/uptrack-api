defmodule Uptrack.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo

  alias Uptrack.Accounts.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    AppAppRepo.all(User)
  end

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
end
