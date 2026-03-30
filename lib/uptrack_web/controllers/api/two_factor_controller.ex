defmodule UptrackWeb.Api.TwoFactorController do
  use UptrackWeb, :controller

  alias Uptrack.Auth

  @doc """
  GET /api/auth/2fa/status
  Returns whether 2FA is enabled for the current user.
  """
  def status(conn, _params) do
    user = conn.assigns.current_user
    json(conn, %{enabled: Auth.totp_enabled?(user.id)})
  end

  @doc """
  POST /api/auth/2fa/setup
  Initiates 2FA setup. Returns secret + QR code URI.
  """
  def setup(conn, _params) do
    user = conn.assigns.current_user

    {:ok, data} = Auth.setup_2fa(user.id)

    json(conn, %{
      otpauth_uri: data.otpauth_uri,
      encoded_secret: data.encoded_secret,
      secret: Base.encode64(data.secret)
    })
  end

  @doc """
  POST /api/auth/2fa/confirm
  Confirms 2FA setup with a valid TOTP code. Returns backup codes.
  """
  def confirm(conn, %{"code" => code, "secret" => encoded_secret}) do
    user = conn.assigns.current_user

    case Base.decode64(encoded_secret) do
      {:ok, secret} ->
        case Auth.confirm_2fa(user.id, secret, code) do
          {:ok, %{backup_codes: codes}} ->
            json(conn, %{backup_codes: codes})

          {:error, :invalid_code} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: %{message: "Invalid TOTP code. Please try again."}})

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: %{message: "Failed to enable 2FA. Please try again."}})
        end

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{message: "Invalid secret encoding."}})
    end
  end

  @doc """
  POST /api/auth/2fa/disable
  Disables 2FA. Requires a valid TOTP or backup code.
  """
  def disable(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    case Auth.disable_2fa(user.id, code) do
      :ok ->
        json(conn, %{ok: true})

      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{message: "Invalid code. Please enter a valid TOTP or backup code."}})
    end
  end
end
