defmodule Mix.Tasks.Uptrack.Oauth.SeedClients do
  @moduledoc """
  Seeds pre-registered OAuth clients for known LLM providers.

  ## Usage

      mix uptrack.oauth.seed_clients

  Idempotent — skips clients that already exist.
  Outputs client_id and client_secret for each created client.

  ## Clients seeded

  - claude-ai: Claude.ai custom connector
  - chatgpt: ChatGPT plugin OAuth
  """

  use Mix.Task

  require Logger

  @shortdoc "Seeds pre-registered OAuth clients for Claude.ai and ChatGPT"

  @clients [
    %{
      id: "claude-ai",
      name: "Claude.ai",
      redirect_uris: ["https://claude.ai/api/auth/oauth/callback"],
      confidential: true
    },
    %{
      id: "chatgpt",
      name: "ChatGPT",
      redirect_uris: ["https://chat.openai.com/aip/plugin-b3b788fe-61c6-45c2-bb22-1b5d7fc2f2db/oauth/callback"],
      confidential: true
    }
  ]

  def run(_args) do
    if Code.ensure_loaded?(Mix.Task) and function_exported?(Mix.Task, :run, 1) do
      Mix.Task.run("app.start")
    else
      Application.ensure_all_started(:uptrack)
    end

    Enum.each(@clients, &seed_client/1)
  end

  defp seed_client(%{id: alias_key} = spec) do
    alias Boruta.Ecto.Admin
    alias Uptrack.AppRepo
    import Ecto.Query

    # Check if a client with this alias already exists (stored in metadata)
    search = Jason.encode!(%{"alias" => alias_key})

    existing =
      from(c in {"oauth_clients", Boruta.Ecto.Client},
        where: fragment("?::jsonb @> ?::jsonb", c.metadata, ^search),
        select: %{id: type(c.id, :string), name: c.name}
      )
      |> AppRepo.one(prefix: "app")

    if existing do
      Mix.shell().info("  [skip] #{alias_key} already exists (id: #{existing.id})")
    else
      create_client(spec)
    end
  rescue
    e ->
      Mix.shell().error("  [error] #{inspect(spec.id)} seed check failed: #{inspect(e)}")
  end

  defp create_client(%{id: alias_key, name: name, redirect_uris: redirect_uris, confidential: confidential}) do
    alias Boruta.Ecto.Admin

    attrs = %{
      name: name,
      redirect_uris: redirect_uris,
      supported_grant_types: ["authorization_code", "refresh_token"],
      confidential: confidential,
      pkce: true,
      metadata: %{"alias" => alias_key}
    }

    case Admin.create_client(attrs) do
      {:ok, client} ->
        Mix.shell().info("  [ok] #{alias_key} created")
        Mix.shell().info("       client_id:     #{client.id}")
        if confidential and client.secret do
          Mix.shell().info("       client_secret: #{client.secret}")
          Mix.shell().info("       redirect_uris: #{inspect(redirect_uris)}")
        end

      {:error, reason} ->
        Mix.shell().error("  [error] #{alias_key} failed: #{inspect(reason)}")
    end
  end
end
