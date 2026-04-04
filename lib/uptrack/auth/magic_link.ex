defmodule Uptrack.Auth.MagicLink do
  @moduledoc """
  Pure token logic for magic link authentication.

  No database calls, no side effects — just token generation and validation.
  All functions are deterministic (except generate_token which uses :crypto).
  """

  @token_bytes 32
  @token_ttl_seconds 15 * 60

  @doc """
  Generates a new magic link token.

  Returns `{raw_token, hashed_token}` where:
  - `raw_token` is the base64url-encoded token sent via email
  - `hashed_token` is the SHA-256 hash stored in the database
  """
  @spec generate_token() :: {String.t(), String.t()}
  def generate_token do
    raw = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)
    hashed = hash_token(raw)
    {raw, hashed}
  end

  @doc "Hashes a raw token with SHA-256."
  @spec hash_token(String.t()) :: String.t()
  def hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  @doc "Checks if a raw token matches a stored hash."
  @spec valid_token?(String.t(), String.t()) :: boolean()
  def valid_token?(raw_token, stored_hash) do
    hash_token(raw_token) == stored_hash
  end

  @doc "Checks if a token record has expired."
  @spec expired?(%{expires_at: DateTime.t()}) :: boolean()
  def expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc "Checks if a token has already been used."
  @spec used?(%{used_at: DateTime.t() | nil}) :: boolean()
  def used?(%{used_at: nil}), do: false
  def used?(%{used_at: _}), do: true

  @doc "Returns the expiry time for a new token."
  @spec expires_at() :: DateTime.t()
  def expires_at do
    DateTime.utc_now()
    |> DateTime.add(@token_ttl_seconds, :second)
    |> DateTime.truncate(:second)
  end

  @doc "Returns the token TTL in seconds."
  def token_ttl_seconds, do: @token_ttl_seconds

  @doc """
  Extracts a display name from an email address.

  Used when auto-creating accounts from magic link signup.

  ## Examples

      iex> name_from_email("john.doe@example.com")
      "John Doe"

      iex> name_from_email("admin@example.com")
      "Admin"
  """
  @spec name_from_email(String.t()) :: String.t()
  def name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
