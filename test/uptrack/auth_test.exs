defmodule Uptrack.AuthTest do
  use Uptrack.DataCase

  alias Uptrack.Auth
  alias Uptrack.Accounts

  @moduletag :capture_log
  @test_password "SecurePass123!"

  defp create_user_with_password do
    email = "auth_test_#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Accounts.register_user_with_organization(%{
        "name" => "Auth Test",
        "email" => email,
        "password" => @test_password
      })

    user
  end

  describe "authenticate/2" do
    test "returns {:ok, user} for valid credentials without 2FA" do
      user = create_user_with_password()

      assert {:ok, authenticated} = Auth.authenticate(user.email, @test_password)
      assert authenticated.id == user.id
    end

    test "returns {:error, :invalid_credentials} for wrong password" do
      user = create_user_with_password()

      assert {:error, :invalid_credentials} = Auth.authenticate(user.email, "wrong")
    end

    test "returns {:error, :invalid_credentials} for nonexistent email" do
      assert {:error, :invalid_credentials} = Auth.authenticate("nobody@example.com", "pass")
    end

    test "returns {:totp_required, user} when 2FA is enabled" do
      user = create_user_with_password()

      # Enable 2FA
      {:ok, setup} = Auth.setup_2fa(user.id)
      code = NimbleTOTP.verification_code(setup.secret)
      {:ok, _} = Auth.confirm_2fa(user.id, setup.secret, code)

      assert {:totp_required, u} = Auth.authenticate(user.email, @test_password)
      assert u.id == user.id
    end
  end

  describe "setup_2fa/1 and confirm_2fa/3" do
    test "setup returns secret and URI" do
      user = create_user_with_password()

      assert {:ok, data} = Auth.setup_2fa(user.id)
      assert is_binary(data.secret)
      assert data.otpauth_uri =~ "otpauth://totp/"
      assert data.otpauth_uri =~ user.email
      assert is_binary(data.encoded_secret)
    end

    test "confirm with valid code enables 2FA and returns backup codes" do
      user = create_user_with_password()

      {:ok, setup} = Auth.setup_2fa(user.id)
      code = NimbleTOTP.verification_code(setup.secret)

      assert {:ok, %{backup_codes: codes}} = Auth.confirm_2fa(user.id, setup.secret, code)
      assert length(codes) == 10
      assert Auth.totp_enabled?(user.id)
    end

    test "confirm with invalid code returns error" do
      user = create_user_with_password()

      {:ok, setup} = Auth.setup_2fa(user.id)

      assert {:error, :invalid_code} = Auth.confirm_2fa(user.id, setup.secret, "000000")
      refute Auth.totp_enabled?(user.id)
    end
  end

  describe "verify_second_factor/2" do
    setup do
      user = create_user_with_password()
      {:ok, setup} = Auth.setup_2fa(user.id)
      code = NimbleTOTP.verification_code(setup.secret)
      {:ok, %{backup_codes: backup_codes}} = Auth.confirm_2fa(user.id, setup.secret, code)

      %{user: user, secret: setup.secret, backup_codes: backup_codes}
    end

    test "accepts valid TOTP code", %{user: user, secret: secret} do
      code = NimbleTOTP.verification_code(secret)
      assert {:ok, u} = Auth.verify_second_factor(user.id, code)
      assert u.id == user.id
    end

    test "accepts valid backup code", %{user: user, backup_codes: codes} do
      assert {:ok, u} = Auth.verify_second_factor(user.id, Enum.at(codes, 0))
      assert u.id == user.id
    end

    test "rejects used backup code", %{user: user, backup_codes: codes} do
      first_code = Enum.at(codes, 0)

      # Use the code once
      assert {:ok, _} = Auth.verify_second_factor(user.id, first_code)

      # Try again — should fail
      assert {:error, :invalid_code} = Auth.verify_second_factor(user.id, first_code)
    end

    test "rejects invalid code", %{user: user} do
      assert {:error, :invalid_code} = Auth.verify_second_factor(user.id, "000000")
    end
  end

  describe "disable_2fa/2" do
    test "disables 2FA with valid code" do
      user = create_user_with_password()

      {:ok, setup} = Auth.setup_2fa(user.id)
      code = NimbleTOTP.verification_code(setup.secret)
      {:ok, _} = Auth.confirm_2fa(user.id, setup.secret, code)

      assert Auth.totp_enabled?(user.id)

      disable_code = NimbleTOTP.verification_code(setup.secret)
      assert :ok = Auth.disable_2fa(user.id, disable_code)
      refute Auth.totp_enabled?(user.id)
    end

    test "rejects invalid code" do
      user = create_user_with_password()

      {:ok, setup} = Auth.setup_2fa(user.id)
      code = NimbleTOTP.verification_code(setup.secret)
      {:ok, _} = Auth.confirm_2fa(user.id, setup.secret, code)

      assert {:error, :invalid_code} = Auth.disable_2fa(user.id, "000000")
      assert Auth.totp_enabled?(user.id)
    end
  end
end
