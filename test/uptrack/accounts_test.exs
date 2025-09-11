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
      confirmed_at: nil
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
      valid_attrs = %{
        name: "some name",
        provider: "some provider",
        email: "some email",
        provider_id: "some provider_id",
        hashed_password: "some hashed_password",
        confirmed_at: ~N[2025-09-10 02:16:00]
      }

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.provider == "some provider"
      assert user.email == "some email"
      assert user.provider_id == "some provider_id"
      assert user.hashed_password == "some hashed_password"
      assert user.confirmed_at == ~N[2025-09-10 02:16:00]
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      update_attrs = %{
        name: "some updated name",
        provider: "some updated provider",
        email: "some updated email",
        provider_id: "some updated provider_id",
        hashed_password: "some updated hashed_password",
        confirmed_at: ~N[2025-09-11 02:16:00]
      }

      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.name == "some updated name"
      assert user.provider == "some updated provider"
      assert user.email == "some updated email"
      assert user.provider_id == "some updated provider_id"
      assert user.hashed_password == "some updated hashed_password"
      assert user.confirmed_at == ~N[2025-09-11 02:16:00]
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
