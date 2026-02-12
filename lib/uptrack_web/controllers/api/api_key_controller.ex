defmodule UptrackWeb.Api.ApiKeyController do
  @moduledoc """
  API endpoints for managing API keys.
  """

  use UptrackWeb, :controller

  alias Uptrack.Accounts.ApiKeys

  def index(conn, _params) do
    %{current_organization: org} = conn.assigns

    api_keys =
      ApiKeys.list_api_keys(org.id)
      |> Enum.map(&serialize_key/1)

    json(conn, %{api_keys: api_keys})
  end

  def create(conn, params) do
    %{current_organization: org, current_user: user} = conn.assigns

    attrs = %{
      name: params["name"] || "Untitled Key",
      organization_id: org.id,
      created_by_id: user.id,
      scopes: params["scopes"] || ["read", "write"],
      expires_at: parse_expires_at(params["expires_at"])
    }

    case ApiKeys.create_api_key(attrs) do
      {:ok, api_key} ->
        conn
        |> put_status(:created)
        |> json(%{
          api_key: serialize_key(api_key),
          # Only returned once at creation
          raw_key: api_key.raw_key,
          message: "Store this key securely. It will not be shown again."
        })

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: errors})
    end
  end

  def delete(conn, %{"id" => id}) do
    %{current_organization: org} = conn.assigns

    api_key = ApiKeys.get_api_key!(org.id, id)

    case ApiKeys.delete_api_key(api_key) do
      {:ok, _} ->
        json(conn, %{success: true, message: "API key deleted"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete API key"})
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "API key not found"})
  end

  def revoke(conn, %{"id" => id}) do
    %{current_organization: org} = conn.assigns

    api_key = ApiKeys.get_api_key!(org.id, id)

    case ApiKeys.revoke_api_key(api_key) do
      {:ok, revoked} ->
        json(conn, %{api_key: serialize_key(revoked), message: "API key revoked"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to revoke API key"})
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "API key not found"})
  end

  defp serialize_key(api_key) do
    %{
      id: api_key.id,
      name: api_key.name,
      key_prefix: api_key.key_prefix,
      scopes: api_key.scopes,
      is_active: api_key.is_active,
      last_used_at: api_key.last_used_at,
      expires_at: api_key.expires_at,
      created_at: api_key.inserted_at
    }
  end

  defp parse_expires_at(nil), do: nil

  defp parse_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_expires_at(_), do: nil
end
