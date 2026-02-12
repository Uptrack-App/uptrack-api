defmodule UptrackWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using the Hammer library.

  ## Configuration

  Configure in your router:

      plug UptrackWeb.Plugs.RateLimit,
        max_requests: 100,
        interval_ms: 60_000,
        by: :ip

  ## Options

  - `:max_requests` - Maximum requests allowed in the interval (default: 100)
  - `:interval_ms` - Time window in milliseconds (default: 60_000 = 1 minute)
  - `:by` - Rate limit key: `:ip`, `:user`, or `:token` (default: :ip)
  - `:bucket` - Custom bucket name prefix (default: "default")
  """

  import Plug.Conn
  require Logger

  @default_max_requests 100
  @default_interval_ms 60_000

  def init(opts) do
    %{
      max_requests: Keyword.get(opts, :max_requests, @default_max_requests),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      by: Keyword.get(opts, :by, :ip),
      bucket: Keyword.get(opts, :bucket, "default")
    }
  end

  def call(conn, opts) do
    key = build_key(conn, opts)
    bucket = "#{opts.bucket}:#{key}"

    case Hammer.check_rate(bucket, opts.interval_ms, opts.max_requests) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(opts.max_requests))
        |> put_resp_header("x-ratelimit-remaining", to_string(max(0, opts.max_requests - count)))
        |> put_resp_header("x-ratelimit-reset", to_string(reset_time(opts.interval_ms)))

      {:deny, _limit} ->
        Logger.warning("Rate limit exceeded for #{bucket}")

        conn
        |> put_resp_header("x-ratelimit-limit", to_string(opts.max_requests))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("x-ratelimit-reset", to_string(reset_time(opts.interval_ms)))
        |> put_resp_header("retry-after", to_string(div(opts.interval_ms, 1000)))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{
          error: "Too many requests",
          message: "Rate limit exceeded. Please try again later.",
          retry_after: div(opts.interval_ms, 1000)
        }))
        |> halt()
    end
  end

  defp build_key(conn, %{by: :ip}) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp build_key(conn, %{by: :user}) do
    case conn.assigns[:current_user] do
      nil -> build_key(conn, %{by: :ip})
      user -> "user:#{user.id}"
    end
  end

  defp build_key(conn, %{by: :token}) do
    case conn.path_params["token"] do
      nil -> build_key(conn, %{by: :ip})
      token -> "token:#{token}"
    end
  end

  defp reset_time(interval_ms) do
    now = System.system_time(:millisecond)
    div(now + interval_ms, 1000)
  end
end
