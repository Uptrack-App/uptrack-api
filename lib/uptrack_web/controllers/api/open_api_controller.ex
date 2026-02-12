defmodule UptrackWeb.Api.OpenApiController do
  use UptrackWeb, :controller

  alias UptrackWeb.ApiSpec

  @doc """
  Serves the OpenAPI specification as JSON.
  """
  def spec(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> json(ApiSpec.spec())
  end
end
