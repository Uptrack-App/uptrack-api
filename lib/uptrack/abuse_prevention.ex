defmodule Uptrack.AbusePrevention do
  @moduledoc """
  Abuse prevention for the free plan.

  Pure validation functions — no side effects. Called from controllers
  and workers to enforce limits on free accounts.

  Disposable email domains loaded from:
  1. Nebulex cache (refreshed daily by DisposableEmailWorker from GitHub)
  2. Compile-time fallback from priv/disposable_email_domains.txt (~72k domains)
  """

  alias Uptrack.Cache

  # Compile-time fallback: load from file into a MapSet
  @external_resource Path.join(:code.priv_dir(:uptrack), "disposable_email_domains.txt")
  @compile_time_domains (
    path = Path.join(:code.priv_dir(:uptrack), "disposable_email_domains.txt")
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> MapSet.new()
    else
      MapSet.new()
    end
  )

  @cache_key :disposable_email_domains

  @private_ip_patterns [
    ~r/^https?:\/\/localhost/i,
    ~r/^https?:\/\/127\./,
    ~r/^https?:\/\/10\./,
    ~r/^https?:\/\/172\.(1[6-9]|2[0-9]|3[01])\./,
    ~r/^https?:\/\/192\.168\./,
    ~r/^https?:\/\/0\.0\.0\.0/,
    ~r/^https?:\/\/\[::1\]/,
    ~r/^https?:\/\/169\.254\./,
  ]

  # --- Email validation ---

  @doc "Checks if an email domain is a known disposable/temporary email provider."
  def disposable_email?(email) when is_binary(email) do
    case String.split(email, "@") do
      [_, domain] ->
        downcased = String.downcase(domain)
        domains = get_domains()
        MapSet.member?(domains, downcased)

      _ ->
        false
    end
  end

  def disposable_email?(_), do: false

  @doc "Returns the domain part of an email address."
  def email_domain(email) when is_binary(email) do
    case String.split(email, "@") do
      [_, domain] -> String.downcase(domain)
      _ -> nil
    end
  end

  @doc "Returns the current domain set (cache or compile-time fallback)."
  def get_domains do
    case Cache.get(@cache_key) do
      nil -> @compile_time_domains
      domains -> domains
    end
  rescue
    # Cache not started yet (during compilation or tests)
    _ -> @compile_time_domains
  end

  @doc "Updates the cached domain set. Called by DisposableEmailWorker."
  def put_domains(%MapSet{} = domains) do
    # Cache for 25 hours (worker runs every 24h, overlap ensures no gap)
    Cache.put(@cache_key, domains, ttl: :timer.hours(25))
  end

  @doc "Returns the count of known disposable domains."
  def domain_count do
    MapSet.size(get_domains())
  end

  # --- URL validation ---

  @doc "Checks if a URL points to a private/localhost IP address."
  def private_url?(url) when is_binary(url) do
    Enum.any?(@private_ip_patterns, &Regex.match?(&1, url))
  end

  def private_url?(_), do: false

  # --- Free plan content limits ---

  @doc "Maximum response body size stored for free plan (1KB)."
  def max_response_body_size("free"), do: 1_000
  def max_response_body_size(_plan), do: 10_000

  @doc "Whether POST/PUT request body is allowed on a plan."
  def request_body_allowed?("free"), do: false
  def request_body_allowed?(_plan), do: true

  @doc "Maximum custom headers allowed on a plan."
  def max_custom_headers("free"), do: 3
  def max_custom_headers(_plan), do: :unlimited

  # --- Account verification ---

  @doc "Checks if a user account is verified (has confirmed_at set)."
  def account_verified?(%{confirmed_at: nil}), do: false
  def account_verified?(%{confirmed_at: _}), do: true
  def account_verified?(_), do: false

  @doc "Checks if monitors should be active for this user. Paid plans skip verification."
  def monitors_allowed?(user, plan) do
    plan != "free" or account_verified?(user)
  end
end
