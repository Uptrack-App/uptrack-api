defmodule Uptrack.Cache do
  @moduledoc """
  Application-level caching using Cachex.

  Provides a get-or-compute pattern for expensive database queries.
  """

  @cache_name :uptrack_cache

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

    Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fun.(), ttl: ttl}
    end)
    |> unwrap()
  end

  @doc """
  Invalidates a specific cache key.
  """
  def invalidate(key) do
    Cachex.del(@cache_name, key)
  end

  @doc """
  Invalidates all cache keys matching a prefix pattern.
  Uses Cachex stream to find and delete matching keys.
  """
  def invalidate_prefix(prefix) do
    Cachex.stream!(@cache_name)
    |> Stream.filter(fn {:entry, key, _touch, _ttl, _val} ->
      is_binary(key) and String.starts_with?(key, prefix)
    end)
    |> Stream.each(fn {:entry, key, _touch, _ttl, _val} ->
      Cachex.del(@cache_name, key)
    end)
    |> Stream.run()
  end

  # Cache key builders

  def dashboard_stats_key(org_id), do: "dashboard_stats:#{org_id}"
  def dashboard_analytics_key(org_id, days), do: "dashboard_analytics:#{org_id}:#{days}"
  def monitor_analytics_key(monitor_id, days), do: "monitor_analytics:#{monitor_id}:#{days}"
  def org_trends_key(org_id, days), do: "org_trends:#{org_id}:#{days}"

  # TTL accessors for callers
  def ttl_short, do: @ttl_short
  def ttl_medium, do: @ttl_medium

  # Unwrap Cachex fetch results
  defp unwrap({:ok, val}), do: val
  defp unwrap({:commit, val}), do: val
  defp unwrap({:commit, val, _opts}), do: val
end
