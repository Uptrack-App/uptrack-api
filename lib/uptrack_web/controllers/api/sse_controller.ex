defmodule UptrackWeb.Api.SSEController do
  @moduledoc """
  Server-Sent Events endpoint for real-time public status page updates.

  Sends a snapshot of current monitor statuses on connect, then streams
  status_change events whenever a monitor flips up/down. No auth required —
  status pages are public.
  """

  use UptrackWeb, :controller

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.MonitorCheck

  def status_stream(conn, %{"slug" => slug}) do
    case Monitoring.get_public_status_page_with_status(slug) do
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Not found"})

      {:ok, status_page} ->
        # Subscribe to PubSub before sending headers to avoid missing events
        Enum.each(status_page.monitors, fn m ->
          Phoenix.PubSub.subscribe(Uptrack.PubSub, "monitor:#{m.id}")
        end)

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("x-accel-buffering", "no")
          |> send_chunked(200)

        snapshot = Jason.encode!(build_snapshot(status_page.monitors))

        with {:ok, conn} <- chunk(conn, "event: snapshot\ndata: #{snapshot}\n\n") do
          sse_loop(conn)
        end
    end
  end

  defp build_snapshot(monitors) do
    %{
      monitors:
        Enum.map(monitors, fn m ->
          latest = List.first(m.monitor_checks)

          %{
            id: m.id,
            name: m.name,
            status: check_status(latest),
            response_time: latest && latest.response_time,
            last_checked_at: latest && latest.checked_at
          }
        end)
    }
  end

  defp sse_loop(conn) do
    receive do
      {:monitor_status_changed, data} ->
        payload =
          Jason.encode!(%{
            monitor_id: data.monitor_id,
            monitor_name: data.monitor_name,
            old_status: data.old_status,
            new_status: data.new_status,
            changed_at: data.changed_at
          })

        case chunk(conn, "event: status_change\ndata: #{payload}\n\n") do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end

      _ ->
        sse_loop(conn)
    after
      30_000 ->
        # Heartbeat keeps Cloudflare tunnel and proxies from closing idle connections
        case chunk(conn, ": heartbeat\n\n") do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  defp check_status(%MonitorCheck{status: status}), do: status
  defp check_status(_), do: "unknown"
end
