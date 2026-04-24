defmodule Uptrack.Cache do
  @moduledoc """
  Application-level caching using Nebulex.

  Provides a get-or-compute pattern for expensive database queries.
  Uses a local (ETS-based) cache adapter.
  """

  use Nebulex.Cache,
    otp_app: :uptrack,
    adapter: Nebulex.Adapters.Local

  # TTLs in milliseconds
  @ttl_short :timer.seconds(60)
  @ttl_medium :timer.minutes(5)

  @doc """
  Fetches a value from cache, computing it if not present.

  ## Options
    * `:ttl` - cache TTL in milliseconds (default: 60s)
  """
  def fetch(key, opts \\ [], fun) do
    ttl = Keyword.get(opts, :ttl, @ttl_short)

    case get(key) do
      nil ->
        value = fun.()
        put(key, value, ttl: ttl)
        value

      value ->
        value
    end
  end

  @doc """
  Invalidates a specific cache key.
  """
  def invalidate(key) do
    delete(key)
  end

  @doc """
  Invalidates all cache keys matching a prefix pattern.
  Clears the entire cache since Nebulex Local adapter doesn't support
  prefix queries. Cache is small and rebuilds quickly.
  """
  def invalidate_prefix(_prefix) do
    delete_all()
  end

  @ttl_check_default :timer.seconds(120)
  @ttl_check_min :timer.seconds(120)
  @ttl_check_max :timer.hours(24)

  @doc """
  Caches the latest check status for a monitor.

  Called by MonitorProcess after every check — always fresh.
  Read by the API listing/detail views instead of querying VM.

  `interval_seconds` (the monitor's check cadence) is used to derive a
  TTL that outlives the gap between checks. Without this, monitors
  with intervals > 120s show "Unknown" in the UI 97% of the time.
  """
  def put_latest_check(monitor_id, check_data, interval_seconds \\ nil) do
    ttl = ttl_for_interval(interval_seconds)
    put("latest_check:#{monitor_id}", check_data, ttl: ttl)
  end

  defp ttl_for_interval(nil), do: @ttl_check_default

  defp ttl_for_interval(seconds) when is_integer(seconds) and seconds > 0 do
    # Two full intervals plus 30s buffer so a missed check doesn't flip
    # the UI to "Unknown" immediately.
    ms = (seconds * 2 + 30) * 1_000
    ms |> max(@ttl_check_min) |> min(@ttl_check_max)
  end

  defp ttl_for_interval(_), do: @ttl_check_default

  def get_latest_check(monitor_id) do
    get("latest_check:#{monitor_id}")
  end

  @doc """
  Gets latest checks for multiple monitors from cache.

  Returns a map of monitor_id => check_data.
  Falls back to nil for uncached monitors.
  """
  def get_latest_checks_batch(monitor_ids) do
    Map.new(monitor_ids, fn id ->
      {to_string(id), get_latest_check(id)}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Cache key builders

  def dashboard_stats_key(org_id), do: "dashboard_stats:#{org_id}"
  def dashboard_analytics_key(org_id, days), do: "dashboard_analytics:#{org_id}:#{days}"
  def monitor_analytics_key(monitor_id, days), do: "monitor_analytics:#{monitor_id}:#{days}"
  def org_trends_key(org_id, days), do: "org_trends:#{org_id}:#{days}"

  # TTL accessors for callers
  def ttl_short, do: @ttl_short
  def ttl_medium, do: @ttl_medium
end
