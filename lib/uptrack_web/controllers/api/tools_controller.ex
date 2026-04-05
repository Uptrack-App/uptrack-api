defmodule UptrackWeb.Api.ToolsController do
  use UptrackWeb, :controller

  alias Uptrack.Tools.WebsiteChecker

  @doc "POST /api/tools/check-website — public, rate-limited"
  def check_website(conn, %{"url" => url}) when is_binary(url) and byte_size(url) > 0 do
    case Hammer.check_rate("tools:check:#{conn.remote_ip |> :inet.ntoa() |> to_string()}", 60_000, 10) do
      {:allow, _} ->
        result = WebsiteChecker.check(url)
        json(conn, %{data: result})

      {:deny, _} ->
        conn
        |> put_status(429)
        |> json(%{error: %{message: "Rate limit exceeded. Try again in a minute."}})
    end
  end

  def check_website(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{message: "URL is required"}})
  end
end
