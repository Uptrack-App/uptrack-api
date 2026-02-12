defmodule Uptrack.OrganizationsTest do
  use Uptrack.DataCase

  alias Uptrack.Organizations
  alias Uptrack.Organizations.Organization
  import Uptrack.MonitoringFixtures

  describe "list_organizations/0" do
    test "returns all organizations" do
      {_user, org} = user_with_org_fixture()
      orgs = Organizations.list_organizations()
      assert Enum.any?(orgs, &(&1.id == org.id))
    end
  end

  describe "get_organization!/1" do
    test "returns the organization with given id" do
      {_user, org} = user_with_org_fixture()
      fetched = Organizations.get_organization!(org.id)
      assert fetched.id == org.id
      assert fetched.name == org.name
    end

    test "raises when organization does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Organizations.get_organization!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_organization/1" do
    test "returns organization or nil" do
      {_user, org} = user_with_org_fixture()
      assert Organizations.get_organization(org.id) != nil
      assert Organizations.get_organization(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_organization_by_slug/1" do
    test "returns organization by slug" do
      {_user, org} = user_with_org_fixture()
      fetched = Organizations.get_organization_by_slug(org.slug)
      assert fetched.id == org.id
    end

    test "returns nil for non-existent slug" do
      assert Organizations.get_organization_by_slug("nonexistent-slug") == nil
    end
  end

  describe "create_organization/1" do
    test "creates organization with valid attrs" do
      attrs = %{name: "Test Org", slug: "test-org-#{System.unique_integer([:positive])}"}
      assert {:ok, %Organization{} = org} = Organizations.create_organization(attrs)
      assert org.name == "Test Org"
    end

    test "enforces unique slug" do
      attrs = %{name: "Org 1", slug: "unique-slug-#{System.unique_integer([:positive])}"}
      assert {:ok, _} = Organizations.create_organization(attrs)
      assert {:error, changeset} = Organizations.create_organization(attrs)
      assert errors_on(changeset).slug != nil
    end
  end

  describe "update_organization/2" do
    test "updates organization with valid attrs" do
      {_user, org} = user_with_org_fixture()
      assert {:ok, updated} = Organizations.update_organization(org, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  describe "delete_organization/1" do
    test "deletes the organization" do
      {_user, org} = user_with_org_fixture()
      assert {:ok, _} = Organizations.delete_organization(org)
      assert Organizations.get_organization(org.id) == nil
    end
  end
end
