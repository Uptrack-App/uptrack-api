defmodule Uptrack.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Uptrack.Accounts` context.
  """

  alias Uptrack.Organizations

  @doc """
  Generate a unique user email.
  """
  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  @doc """
  Generate an organization.
  """
  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      attrs
      |> Enum.into(%{
        name: "Test Organization #{System.unique_integer([:positive])}",
        slug: "test-org-#{System.unique_integer([:positive])}"
      })
      |> Organizations.create_organization()

    organization
  end

  @doc """
  Generate a user with an organization.
  """
  def user_fixture(attrs \\ %{}) do
    org_id =
      case attrs[:organization_id] do
        nil ->
          org = organization_fixture()
          org.id

        org_id ->
          org_id
      end

    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: unique_user_email(),
        name: "Test User",
        password: "secure_password_123",
        organization_id: org_id
      })
      |> Uptrack.Accounts.create_user()

    user
  end

  @doc """
  Generate a user with organization, returning both.
  """
  def user_with_org_fixture(attrs \\ %{}) do
    org = organization_fixture(attrs[:organization] || %{})

    {:ok, user} =
      attrs
      |> Map.delete(:organization)
      |> Enum.into(%{
        email: unique_user_email(),
        name: "Test User",
        password: "secure_password_123",
        organization_id: org.id
      })
      |> Uptrack.Accounts.create_user()

    {user, org}
  end
end
