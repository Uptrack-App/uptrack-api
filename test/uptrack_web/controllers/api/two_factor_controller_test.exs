defmodule UptrackWeb.Api.TwoFactorControllerTest do
  use UptrackWeb.ConnCase

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/auth/2fa/status" do
    test "returns false when 2FA not enabled", %{conn: conn} do
      conn = get(conn, "/api/auth/2fa/status")
      assert json_response(conn, 200)["enabled"] == false
    end
  end

  describe "POST /api/auth/2fa/setup" do
    test "returns QR code data", %{conn: conn} do
      conn = post(conn, "/api/auth/2fa/setup")
      response = json_response(conn, 200)

      assert response["otpauth_uri"] =~ "otpauth://totp/"
      assert is_binary(response["encoded_secret"])
      assert is_binary(response["secret"])
    end
  end

  describe "POST /api/auth/2fa/confirm" do
    test "enables 2FA with valid code", %{conn: conn} do
      # Setup
      setup_conn = post(conn, "/api/auth/2fa/setup")
      setup_data = json_response(setup_conn, 200)

      # Generate valid code
      {:ok, secret} = Base.decode64(setup_data["secret"])
      code = NimbleTOTP.verification_code(secret)

      # Confirm
      confirm_conn = post(conn, "/api/auth/2fa/confirm", %{
        "code" => code,
        "secret" => setup_data["secret"]
      })

      response = json_response(confirm_conn, 200)
      assert is_list(response["backup_codes"])
      assert length(response["backup_codes"]) == 10

      # Verify enabled
      status_conn = get(conn, "/api/auth/2fa/status")
      assert json_response(status_conn, 200)["enabled"] == true
    end

    test "rejects invalid code", %{conn: conn} do
      setup_conn = post(conn, "/api/auth/2fa/setup")
      setup_data = json_response(setup_conn, 200)

      conn = post(conn, "/api/auth/2fa/confirm", %{
        "code" => "000000",
        "secret" => setup_data["secret"]
      })

      assert json_response(conn, 422)["error"]
    end
  end
end
