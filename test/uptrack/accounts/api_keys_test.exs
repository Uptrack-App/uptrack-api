defmodule Uptrack.Accounts.ApiKeysTest do
  use Uptrack.DataCase

  alias Uptrack.Accounts.{ApiKey, ApiKeys}

  import Uptrack.MonitoringFixtures

  setup do
    {user, org} = user_with_org_fixture()
    {:ok, user: user, org: org}
  end

  describe "create_api_key/1" do
    test "creates an API key with valid attrs", %{user: user, org: org} do
      assert {:ok, api_key} =
               ApiKeys.create_api_key(%{
                 name: "Test Key",
                 organization_id: org.id,
                 created_by_id: user.id
               })

      assert api_key.name == "Test Key"
      assert api_key.is_active == true
      assert String.starts_with?(api_key.raw_key, "utk_")
      assert String.starts_with?(api_key.key_prefix, "utk_")
      assert is_binary(api_key.key_hash)
    end

    test "returns error with missing name", %{user: user, org: org} do
      assert {:error, changeset} =
               ApiKeys.create_api_key(%{
                 name: nil,
                 organization_id: org.id,
                 created_by_id: user.id
               })

      assert errors_on(changeset)[:name] != nil
    end
  end

  describe "authenticate_by_key/1" do
    test "authenticates with valid key", %{user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{
          name: "Auth Test",
          organization_id: org.id,
          created_by_id: user.id
        })

      assert {:ok, found} = ApiKeys.authenticate_by_key(api_key.raw_key)
      assert found.id == api_key.id
    end

    test "rejects invalid key" do
      assert {:error, :invalid_key} = ApiKeys.authenticate_by_key("utk_invalid_key")
    end

    test "rejects revoked key", %{user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{
          name: "Revoke Test",
          organization_id: org.id,
          created_by_id: user.id
        })

      raw_key = api_key.raw_key
      {:ok, _} = ApiKeys.revoke_api_key(api_key)

      assert {:error, :invalid_key} = ApiKeys.authenticate_by_key(raw_key)
    end

    test "rejects expired key", %{user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{
          name: "Expired Test",
          organization_id: org.id,
          created_by_id: user.id,
          expires_at: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
        })

      assert {:error, :expired_key} = ApiKeys.authenticate_by_key(api_key.raw_key)
    end

    test "updates last_used_at on successful auth", %{user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{
          name: "Touch Test",
          organization_id: org.id,
          created_by_id: user.id
        })

      assert is_nil(api_key.last_used_at)

      {:ok, _} = ApiKeys.authenticate_by_key(api_key.raw_key)

      updated = ApiKeys.get_api_key!(org.id, api_key.id)
      assert not is_nil(updated.last_used_at)
    end
  end

  describe "list_api_keys/1" do
    test "lists keys for an organization", %{user: user, org: org} do
      {:ok, _} =
        ApiKeys.create_api_key(%{name: "Key 1", organization_id: org.id, created_by_id: user.id})

      {:ok, _} =
        ApiKeys.create_api_key(%{name: "Key 2", organization_id: org.id, created_by_id: user.id})

      keys = ApiKeys.list_api_keys(org.id)
      assert length(keys) == 2
    end

    test "doesn't list keys from other organizations", %{user: user, org: org} do
      {:ok, _} =
        ApiKeys.create_api_key(%{name: "My Key", organization_id: org.id, created_by_id: user.id})

      {_other_user, other_org} = user_with_org_fixture()
      assert ApiKeys.list_api_keys(other_org.id) == []
    end
  end

  describe "revoke_api_key/1" do
    test "deactivates the key", %{user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{name: "Revoke Me", organization_id: org.id, created_by_id: user.id})

      assert {:ok, revoked} = ApiKeys.revoke_api_key(api_key)
      assert revoked.is_active == false
    end
  end

  describe "ApiKey.hash_key/1" do
    test "produces deterministic hash" do
      key = "utk_test_key_12345"
      assert ApiKey.hash_key(key) == ApiKey.hash_key(key)
    end

    test "different keys produce different hashes" do
      assert ApiKey.hash_key("utk_key_a") != ApiKey.hash_key("utk_key_b")
    end
  end
end
