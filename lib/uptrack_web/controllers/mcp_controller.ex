defmodule UptrackWeb.MCPController do
  @moduledoc "HTTP endpoint for MCP protocol communication."

  use UptrackWeb, :controller

  alias Uptrack.MCP.Server

  require Logger

  def index(conn, _params) do
    org = conn.assigns.current_organization

    case get_body_json(conn) do
      {:ok, body_json} ->
        response_json = Server.handle_message(body_json, org.id)

        conn
        |> put_resp_content_type("application/json", "utf-8")
        |> send_resp(200, response_json)

      {:error, :no_body} ->
        conn
        |> put_status(:bad_request)
        |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32_700, message: "Parse error"}})
    end
  rescue
    e ->
      Logger.error("MCP HTTP error: #{Exception.format(:error, e, __STACKTRACE__)}")

      conn
      |> put_status(:internal_server_error)
      |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32_603, message: "Internal error"}})
  end

  defp get_body_json(conn) do
    case conn.body_params do
      params when is_map(params) and map_size(params) > 0 ->
        case Jason.encode(params) do
          {:ok, json} -> {:ok, json}
          {:error, _} -> {:error, :no_body}
        end

      _ ->
        {:error, :no_body}
    end
  end
end
