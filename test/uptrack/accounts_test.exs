defmodule Uptrack.AccountsTest do
  use Uptrack.DataCase

  alias Uptrack.Accounts

  describe "users" do
    alias Uptrack.Accounts.User

    import Uptrack.AccountsFixtures

    @invalid_attrs %{
      name: nil,
      provider: nil,
      email: nil,
      provider_id: nil,
      hashed_password: nil,
      confirmed_at: nil,
      organization_id: nil
    }

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      org = organization_fixture()

      valid_attrs = %{
        name: "Test User",
        email: "test@example.com",
        password: "secure_password_123",
        organization_id: org.id
      }

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.name == "Test User"
      assert user.email == "test@example.com"
      assert user.organization_id == org.id
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      update_attrs = %{
        name: "Updated Name",
        email: "updated@example.com"
      }

      assert {:ok, %User{} = updated_user} = Accounts.update_user(user, update_attrs)
      assert updated_user.name == "Updated Name"
      assert updated_user.email == "updated@example.com"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user(user, @invalid_attrs)
      assert user == Accounts.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Accounts.change_user(user)
    end
  end
end
