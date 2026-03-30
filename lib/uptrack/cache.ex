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

  # Cache key builders

  def dashboard_stats_key(org_id), do: "dashboard_stats:#{org_id}"
  def dashboard_analytics_key(org_id, days), do: "dashboard_analytics:#{org_id}:#{days}"
  def monitor_analytics_key(monitor_id, days), do: "monitor_analytics:#{monitor_id}:#{days}"
  def org_trends_key(org_id, days), do: "org_trends:#{org_id}:#{days}"

  # TTL accessors for callers
  def ttl_short, do: @ttl_short
  def ttl_medium, do: @ttl_medium
end
