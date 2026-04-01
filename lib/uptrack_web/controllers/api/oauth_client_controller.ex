defmodule UptrackWeb.Api.OAuthClientController do
  @moduledoc "CRUD for OAuth clients in Dashboard Settings > Integrations."

  use UptrackWeb, :controller

  alias Uptrack.OAuth

  def index(conn, _params) do
    org = conn.assigns.current_organization
    clients = OAuth.list_clients(org.id)
    json(conn, %{clients: clients})
  end

  def create(conn, params) do
    org = conn.assigns.current_organization

    attrs = Map.put(params, "organization_id", org.id)

    case OAuth.create_client(attrs) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: client.id,
          name: client.name,
          client_id: client.id,
          client_secret: client.secret,
          redirect_uris: client.redirect_uris
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create client", details: inspect(changeset.errors)})
    end
  end

  def delete(conn, %{"id" => id}) do
    case OAuth.delete_client(id) do
      {:ok, _} -> json(conn, %{deleted: true})
      _ -> conn |> put_status(:not_found) |> json(%{error: "Client not found"})
    end
  end
end
