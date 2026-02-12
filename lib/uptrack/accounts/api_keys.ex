defmodule Uptrack.Accounts.ApiKeys do
  @moduledoc """
  Context for managing API keys.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Uptrack.Accounts.ApiKey

  def list_api_keys(organization_id) do
    ApiKey
    |> where([k], k.organization_id == ^organization_id)
    |> order_by([k], desc: k.inserted_at)
    |> AppRepo.all()
  end

  def get_api_key!(organization_id, id) do
    ApiKey
    |> where([k], k.id == ^id and k.organization_id == ^organization_id)
    |> AppRepo.one!()
  end

  def create_api_key(attrs) do
    %ApiKey{}
    |> ApiKey.create_changeset(attrs)
    |> AppRepo.insert()
  end

  def revoke_api_key(%ApiKey{} = api_key) do
    api_key
    |> Ecto.Changeset.change(is_active: false)
    |> AppRepo.update()
  end

  def delete_api_key(%ApiKey{} = api_key) do
    AppRepo.delete(api_key)
  end

  def authenticate_by_key(raw_key) do
    key_hash = ApiKey.hash_key(raw_key)

    case AppRepo.one(from k in ApiKey, where: k.key_hash == ^key_hash and k.is_active == true) do
      nil ->
        {:error, :invalid_key}

      %ApiKey{} = api_key ->
        if ApiKey.expired?(api_key) do
          {:error, :expired_key}
        else
          touch_last_used(api_key)
          {:ok, api_key}
        end
    end
  end

  defp touch_last_used(%ApiKey{} = api_key) do
    api_key
    |> Ecto.Changeset.change(last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> AppRepo.update()
  end
end
