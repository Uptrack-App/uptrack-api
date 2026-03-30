defmodule Uptrack.Auth.TotpTest do
  use ExUnit.Case, async: true

  alias Uptrack.Auth.Totp

  describe "generate_secret/0" do
    test "returns a 20-byte binary" do
      secret = Totp.generate_secret()
      assert is_binary(secret)
      assert byte_size(secret) == 20
    end

    test "generates unique secrets" do
      secrets = Enum.map(1..10, fn _ -> Totp.generate_secret() end)
      assert length(Enum.uniq(secrets)) == 10
    end
  end

  describe "otpauth_uri/2" do
    test "returns a valid otpauth URI" do
      secret = Totp.generate_secret()
      uri = Totp.otpauth_uri(secret, "test@example.com")

      assert String.starts_with?(uri, "otpauth://totp/Uptrack:")
      assert uri =~ "test@example.com"
      assert uri =~ "issuer=Uptrack"
    end
  end

  describe "verify_code/2" do
    test "accepts a valid current code" do
      secret = Totp.generate_secret()
      code = NimbleTOTP.verification_code(secret)

      assert Totp.verify_code(secret, code) == true
    end

    test "rejects an invalid code" do
      secret = Totp.generate_secret()
      assert Totp.verify_code(secret, "000000") == false
    end

    test "rejects non-string input" do
      secret = Totp.generate_secret()
      assert Totp.verify_code(secret, nil) == false
      assert Totp.verify_code(secret, 123456) == false
    end
  end

  describe "encode_secret/1" do
    test "returns a Base32 string" do
      secret = Totp.generate_secret()
      encoded = Totp.encode_secret(secret)

      assert is_binary(encoded)
      assert {:ok, ^secret} = Base.decode32(encoded, padding: false)
    end
  end
end
