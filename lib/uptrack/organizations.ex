defmodule Uptrack.Organizations do
  @moduledoc """
  The Organizations context.

  Organizations are the root tenant entity. All users, monitors, and other
  resources belong to an organization. This enables multi-tenancy and
  team collaboration features.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Uptrack.Organizations.Organization

  @doc """
  Returns the list of organizations.
  """
  def list_organizations do
    AppRepo.all(Organization)
  end

  @doc """
  Gets a single organization by ID.

  Raises `Ecto.NoResultsError` if the Organization does not exist.
  """
  def get_organization!(id), do: AppRepo.get!(Organization, id)

  @doc """
  Gets a single organization by ID.

  Returns `nil` if the Organization does not exist.
  """
  def get_organization(id), do: AppRepo.get(Organization, id)

  @doc """
  Gets a single organization by slug.

  Returns `nil` if the Organization does not exist.
  """
  def get_organization_by_slug(slug) do
    AppRepo.get_by(Organization, slug: slug)
  end

  @doc """
  Creates an organization.
  """
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.create_changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates an organization.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes an organization.
  """
  def delete_organization(%Organization{} = organization) do
    AppRepo.delete(organization)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking organization changes.
  """
  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
  end

  @doc """
  Gets the organization for a user.
  """
  def get_user_organization(user) do
    get_organization(user.organization_id)
  end

  @doc """
  Lists all users in an organization.
  """
  def list_organization_users(%Organization{} = organization) do
    alias Uptrack.Accounts.User

    User
    |> where([u], u.organization_id == ^organization.id)
    |> AppRepo.all()
  end

  @doc """
  Counts members in an organization.
  """
  def count_organization_members(%Organization{} = organization) do
    alias Uptrack.Accounts.User

    User
    |> where([u], u.organization_id == ^organization.id)
    |> AppRepo.aggregate(:count)
  end
end
