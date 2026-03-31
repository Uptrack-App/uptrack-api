defmodule UptrackWeb.Api.MCPController do
  @moduledoc "HTTP endpoint for MCP protocol communication."

  use UptrackWeb, :controller

  alias Uptrack.MCP.Server

  require Logger

  def index(conn, params) do
    org = conn.assigns.current_organization

    if map_size(params) > 0 do
      body_json = Jason.encode!(params)
      response_json = Server.handle_message(body_json, org.id)

      conn
      |> put_resp_content_type("application/json", "utf-8")
      |> send_resp(200, response_json)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32_700, message: "Parse error"}})
    end
  catch
    kind, reason ->
      Logger.error("MCP HTTP #{kind}: #{Exception.format(kind, reason, __STACKTRACE__)}")

      conn
      |> put_status(:internal_server_error)
      |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32_603, message: "Internal error"}})
  end
end
