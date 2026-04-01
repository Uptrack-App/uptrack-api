defmodule Uptrack.OAuthFixtures do
  @moduledoc "Test helpers for creating OAuth clients and tokens."

  alias Boruta.Ecto.Admin
  alias Uptrack.AppRepo

  @doc "Creates a Boruta OAuth client for an organization."
  def oauth_client_fixture(org_id, attrs \\ %{}) do
    {:ok, client} =
      Admin.create_client(%{
        name: attrs[:name] || "Test Client",
        redirect_uris: attrs[:redirect_uris] || ["https://example.com/callback"],
        supported_grant_types: ["authorization_code", "refresh_token"],
        confidential: true,
        pkce: true,
        metadata: %{"organization_id" => org_id}
      })

    client
  end

  @doc """
  Creates an OAuth access token directly in the database for testing.

  Returns the token value string.
  """
  def oauth_token_fixture(client, org_id, opts \\ []) do
    scope = opts[:scope] || "monitors:read incidents:read analytics:read"
    token_value = "atupt-test-#{Ecto.UUID.generate()}"
    expires_at = System.system_time(:second) + (opts[:ttl] || 86_400)

    {:ok, token_id} = Ecto.UUID.dump(Ecto.UUID.generate())
    {:ok, client_id_binary} = Ecto.UUID.dump(client.id)

    AppRepo.insert_all("oauth_tokens", [
      %{
        id: token_id,
        type: "access_token",
        value: token_value,
        scope: scope,
        expires_at: expires_at,
        sub: "org:#{org_id}",
        client_id: client_id_binary,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    ])

    token_value
  end

  @doc "Creates an expired OAuth token for testing."
  def expired_oauth_token_fixture(client, org_id) do
    oauth_token_fixture(client, org_id, ttl: -3600)
  end
end
