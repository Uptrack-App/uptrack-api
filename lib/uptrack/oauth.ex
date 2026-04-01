defmodule Uptrack.OAuth do
  @moduledoc """
  OAuth 2.0 context for managing OAuth clients.

  Public API for creating, listing, and revoking OAuth clients
  used by third-party integrations (Claude.ai, custom apps).
  """

  import Ecto.Query

  alias Boruta.Ecto.Admin
  alias Uptrack.AppRepo

  @doc "Lists OAuth clients for an organization."
  def list_clients(organization_id) do
    from(c in "oauth_clients",
      where: fragment("?->>'organization_id' = ?", c.metadata, ^organization_id),
      select: %{
        id: type(c.id, :string),
        name: c.name,
        redirect_uris: c.redirect_uris,
        inserted_at: c.inserted_at
      }
    )
    |> AppRepo.all()
  end

  @doc "Creates a new OAuth client for an organization."
  def create_client(attrs) do
    client_attrs = %{
      name: attrs["name"],
      redirect_uris: List.wrap(attrs["redirect_uris"]),
      supported_grant_types: ["authorization_code", "refresh_token"],
      confidential: true,
      pkce: true,
      metadata: %{"organization_id" => attrs["organization_id"]}
    }

    Admin.create_client(client_attrs)
  end

  @doc "Deletes an OAuth client by ID."
  def delete_client(client_id) do
    client = Admin.get_client!(client_id)
    Admin.delete_client(client)
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  @doc "Gets an OAuth client by ID."
  def get_client(client_id) do
    {:ok, Admin.get_client!(client_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
