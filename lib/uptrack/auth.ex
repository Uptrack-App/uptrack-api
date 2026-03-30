defmodule Uptrack.Auth do
  @moduledoc """
  Authentication context — handles login verification and 2FA.

  Separates authentication (verifying identity) from accounts (managing user data).
  Pure logic lives in `Auth.Totp` and `Auth.BackupCodes`; this module
  handles the impure DB operations.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Accounts
  alias Uptrack.Accounts.User
  alias Uptrack.Auth.{Totp, BackupCodes, TotpCredential}

  # --- Authentication ---

  @doc """
  Authenticates a user by email and password.

  Returns:
  - `{:ok, user}` — credentials valid, no 2FA
  - `{:totp_required, user}` — credentials valid, 2FA enabled, need TOTP code
  - `{:error, :invalid_credentials}` — bad email or password
  """
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        if User.valid_password?(user, password) do
          if totp_enabled?(user.id) do
            {:totp_required, user}
          else
            {:ok, user}
          end
        else
          {:error, :invalid_credentials}
        end

      nil ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Verifies a TOTP code or backup code for a user.

  Returns `{:ok, user}` or `{:error, :invalid_code}`.
  """
  def verify_second_factor(user_id, code) when is_binary(code) do
    case get_totp_credential(user_id) do
      nil ->
        {:error, :invalid_code}

      credential ->
        cond do
          Totp.verify_code(credential.secret, code) ->
            {:ok, AppRepo.get!(User, user_id)}

          match?({:ok, _}, BackupCodes.verify(code, credential.backup_codes)) ->
            {:ok, index} = BackupCodes.verify(code, credential.backup_codes)

            case mark_backup_code_used(credential, index) do
              {:ok, _} -> :ok
              {:error, reason} ->
                Logger.warning("Failed to mark backup code used for user #{user_id}: #{inspect(reason)}")
            end

            {:ok, AppRepo.get!(User, user_id)}

          true ->
            {:error, :invalid_code}
        end
    end
  end

  # --- 2FA Setup ---

  @doc """
  Initiates 2FA setup for a user.

  Returns `{:ok, %{secret: binary, otpauth_uri: string, encoded_secret: string}}`
  The secret is NOT saved until `confirm_2fa/2` is called with a valid code.
  """
  def setup_2fa(user_id) do
    secret = Totp.generate_secret()
    user = AppRepo.get!(User, user_id)

    {:ok, %{
      secret: secret,
      otpauth_uri: Totp.otpauth_uri(secret, user.email),
      encoded_secret: Totp.encode_secret(secret)
    }}
  end

  @doc """
  Confirms 2FA setup by verifying the user can generate valid codes.

  Saves the TOTP credential and generates backup codes.
  Returns `{:ok, %{backup_codes: [plaintext_codes]}}` on success.
  """
  def confirm_2fa(user_id, secret, code) when is_binary(code) do
    if Totp.verify_code(secret, code) do
      plaintext_codes = BackupCodes.generate()
      hashed_codes = BackupCodes.hash_all(plaintext_codes)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        %TotpCredential{}
        |> TotpCredential.changeset(%{
          user_id: user_id,
          secret: secret,
          backup_codes: hashed_codes,
          enabled_at: now
        })
        |> AppRepo.insert(
          on_conflict: {:replace, [:secret, :backup_codes, :enabled_at, :updated_at]},
          conflict_target: :user_id
        )

      case result do
        {:ok, _} -> {:ok, %{backup_codes: plaintext_codes}}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Disables 2FA for a user after verifying their identity.

  Requires a valid TOTP code or backup code.
  """
  def disable_2fa(user_id, code) when is_binary(code) do
    case verify_second_factor(user_id, code) do
      {:ok, _user} ->
        from(c in TotpCredential, where: c.user_id == ^user_id)
        |> AppRepo.delete_all()

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Query helpers ---

  @doc """
  Returns whether a user has 2FA enabled.
  """
  def totp_enabled?(user_id) do
    from(c in TotpCredential, where: c.user_id == ^user_id)
    |> AppRepo.exists?()
  end

  defp get_totp_credential(user_id) do
    AppRepo.get_by(TotpCredential, user_id: user_id)
  end

  defp mark_backup_code_used(credential, index) do
    updated_codes =
      credential.backup_codes
      |> List.update_at(index, fn entry ->
        entry |> Map.put("used", true) |> Map.put(:used, true)
      end)

    credential
    |> TotpCredential.changeset(%{backup_codes: updated_codes})
    |> AppRepo.update()
  end
end
