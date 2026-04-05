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

  @doc "GET /api/tools/cluster-health — check all nodes"
  def cluster_health(conn, _params) do
    workers = Node.list() |> Enum.filter(fn n -> String.starts_with?(Atom.to_string(n), "uptrack_worker") end)

    worker_health = Enum.map(workers, fn node ->
      try do
        :erpc.call(node, UptrackWorker.Tools, :health, [], 5_000)
      catch
        _, _ -> %{status: "unreachable", node: node}
      end
    end)

    local = %{
      status: "ok",
      node: node(),
      region: Application.get_env(:uptrack, :node_region, "eu"),
      monitors: Uptrack.Monitoring.MonitorRegistry.count(),
      memory_mb: Float.round(:erlang.memory(:total) / 1_048_576, 1),
      beam_procs: :erlang.system_info(:process_count),
      connected_nodes: length(Node.list())
    }

    json(conn, %{data: %{local: local, workers: worker_health}})
  end
end
