defmodule UptrackWeb.Plugs.RateLimitTest do
  use UptrackWeb.ConnCase

  alias UptrackWeb.Plugs.RateLimit

  @moduletag :capture_log

  describe "init/1" do
    test "uses defaults when no opts" do
      opts = RateLimit.init([])
      assert opts.max_requests == 100
      assert opts.interval_ms == 60_000
      assert opts.by == :ip
      assert opts.bucket == "default"
    end

    test "accepts custom opts" do
      opts = RateLimit.init(max_requests: 5, interval_ms: 1000, by: :user, bucket: "test")
      assert opts.max_requests == 5
      assert opts.interval_ms == 1000
      assert opts.by == :user
      assert opts.bucket == "test"
    end
  end

  describe "call/2" do
    test "allows requests under limit" do
      opts = RateLimit.init(max_requests: 10, interval_ms: 60_000, bucket: "test_allow_#{System.unique_integer([:positive])}")

      conn =
        build_conn()
        |> RateLimit.call(opts)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["10"]
      [remaining] = get_resp_header(conn, "x-ratelimit-remaining")
      assert String.to_integer(remaining) >= 0
    end

    test "returns 429 when limit exceeded" do
      bucket = "test_exceed_#{System.unique_integer([:positive])}"
      opts = RateLimit.init(max_requests: 2, interval_ms: 60_000, bucket: bucket)

      # Use up the limit
      build_conn() |> RateLimit.call(opts)
      build_conn() |> RateLimit.call(opts)

      # Third request should be denied
      conn = build_conn() |> RateLimit.call(opts)

      assert conn.halted
      assert conn.status == 429
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["0"]
      assert get_resp_header(conn, "retry-after") != []

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Too many requests"
    end

    test "sets rate limit headers" do
      opts = RateLimit.init(max_requests: 50, interval_ms: 30_000, bucket: "test_headers_#{System.unique_integer([:positive])}")

      conn = build_conn() |> RateLimit.call(opts)

      assert get_resp_header(conn, "x-ratelimit-limit") == ["50"]
      assert get_resp_header(conn, "x-ratelimit-reset") != []
    end

    test "uses user-based key when by: :user" do
      opts = RateLimit.init(max_requests: 2, interval_ms: 60_000, by: :user, bucket: "test_user_#{System.unique_integer([:positive])}")

      # Without user, falls back to IP
      conn = build_conn() |> RateLimit.call(opts)
      refute conn.halted
    end
  end
end
