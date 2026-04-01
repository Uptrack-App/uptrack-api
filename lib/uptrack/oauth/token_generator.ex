defmodule Uptrack.OAuth.TokenGenerator do
  @moduledoc """
  Custom token format: {prefix}-{env}-{uuid}

  - Access tokens: atupt-prod-{uuid}
  - Refresh tokens: rtupt-prod-{uuid}
  - Client secrets: csupt-prod-{uuid}
  """

  @behaviour Boruta.Oauth.TokenGenerator

  @impl true
  def generate(:access_token, _token) do
    "atupt-#{env()}-#{Ecto.UUID.generate()}"
  end

  def generate(:refresh_token, _token) do
    "rtupt-#{env()}-#{Ecto.UUID.generate()}"
  end

  @impl true
  def secret(_client) do
    "csupt-#{env()}-#{Ecto.UUID.generate()}"
  end

  defp env do
    if Application.get_env(:uptrack, :env) == :prod, do: "prod", else: "dev"
  end
end
