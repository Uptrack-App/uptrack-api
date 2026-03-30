defmodule Uptrack.Auth.Totp do
  @moduledoc """
  Pure TOTP operations — no database, no side effects.

  Generates secrets, builds otpauth URIs, and verifies codes.
  Wraps `NimbleTOTP` with Uptrack-specific defaults.
  """

  @issuer "Uptrack"
  @period 30

  @doc """
  Generates a new random TOTP secret (20 bytes).
  """
  def generate_secret do
    NimbleTOTP.secret()
  end

  @doc """
  Builds an otpauth URI for QR code generation.

      iex> Totp.otpauth_uri(secret, "user@example.com")
      "otpauth://totp/Uptrack:user@example.com?secret=...&issuer=Uptrack"
  """
  def otpauth_uri(secret, email) do
    NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
  end

  @doc """
  Verifies a TOTP code against a secret.

  Accepts the current code and one period before/after to account for clock drift.
  Returns `true` if valid, `false` otherwise.
  """
  def verify_code(secret, code) when is_binary(code) do
    # Allow 1 period of drift in each direction
    NimbleTOTP.valid?(secret, code, period: @period)
  end

  def verify_code(_secret, _code), do: false

  @doc """
  Returns the Base32-encoded secret for display to the user.
  """
  def encode_secret(secret) do
    Base.encode32(secret, padding: false)
  end
end
