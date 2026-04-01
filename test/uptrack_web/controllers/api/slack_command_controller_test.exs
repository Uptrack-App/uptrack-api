defmodule UptrackWeb.Api.SlackCommandControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    # No signing secret configured = skip verification (dev mode)
    Application.delete_env(:uptrack, :slack_signing_secret)
    :ok
  end

  describe "POST /api/slack/commands" do
    test "help command returns usage info", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "help", "team_id" => "T123"})

      assert %{"response_type" => "ephemeral", "text" => text} = json_response(conn, 200)
      assert text =~ "/uptrack status"
      assert text =~ "/uptrack list"
      assert text =~ "/uptrack help"
    end

    test "empty text returns help", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "", "team_id" => "T123"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "/uptrack"
    end

    test "unknown command returns error", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "foobar", "team_id" => "T123"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "Unknown command"
      assert text =~ "foobar"
    end

    test "status command with no connected workspace", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "status", "team_id" => "T_UNKNOWN"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "isn't connected"
    end

    test "list command with no connected workspace", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "list", "team_id" => "T_UNKNOWN"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "isn't connected"
    end

    test "status command with connected workspace shows counts", %{conn: conn} do
      {user, org} = user_with_org_fixture()

      # Create a Slack alert channel with team_id
      alert_channel_fixture(
        organization_id: org.id,
        user_id: user.id,
        type: "slack",
        config: %{"team_id" => "T_TEST_123", "channel" => "#general", "webhook_url" => "https://hooks.slack.com/test"}
      )

      # Create some monitors
      monitor_fixture(organization_id: org.id, user_id: user.id)
      monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = post(conn, "/api/slack/commands", %{"text" => "status", "team_id" => "T_TEST_123"})

      assert %{"response_type" => "in_channel", "text" => text} = json_response(conn, 200)
      assert text =~ "Monitoring Status"
      assert text =~ "2 monitors"
    end

    test "status command shows all operational when no monitors down", %{conn: conn} do
      {user, org} = user_with_org_fixture()

      alert_channel_fixture(
        organization_id: org.id,
        user_id: user.id,
        type: "slack",
        config: %{"team_id" => "T_ALL_UP", "channel" => "#alerts", "webhook_url" => "https://hooks.slack.com/test"}
      )

      monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = post(conn, "/api/slack/commands", %{"text" => "status", "team_id" => "T_ALL_UP"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "operational"
    end

    test "list command with connected workspace shows monitors", %{conn: conn} do
      {user, org} = user_with_org_fixture()

      alert_channel_fixture(
        organization_id: org.id,
        user_id: user.id,
        type: "slack",
        config: %{"team_id" => "T_LIST_123", "channel" => "#alerts", "webhook_url" => "https://hooks.slack.com/test"}
      )

      monitor_fixture(organization_id: org.id, user_id: user.id, url: "https://example.com")

      conn = post(conn, "/api/slack/commands", %{"text" => "list", "team_id" => "T_LIST_123"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "example.com"
    end

    test "list command with no monitors shows create prompt", %{conn: conn} do
      {user, org} = user_with_org_fixture()

      alert_channel_fixture(
        organization_id: org.id,
        user_id: user.id,
        type: "slack",
        config: %{"team_id" => "T_EMPTY", "channel" => "#alerts", "webhook_url" => "https://hooks.slack.com/test"}
      )

      conn = post(conn, "/api/slack/commands", %{"text" => "list", "team_id" => "T_EMPTY"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "No monitors found"
    end

    test "command text is case-insensitive", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "HELP", "team_id" => "T123"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "/uptrack"
    end

    test "command text is trimmed", %{conn: conn} do
      conn = post(conn, "/api/slack/commands", %{"text" => "  help  ", "team_id" => "T123"})

      assert %{"text" => text} = json_response(conn, 200)
      assert text =~ "/uptrack"
    end
  end

  describe "signature verification" do
    test "rejects invalid signature when signing secret is configured", %{conn: conn} do
      Application.put_env(:uptrack, :slack_signing_secret, "test_secret_123")

      conn =
        conn
        |> put_req_header("x-slack-request-timestamp", "1234567890")
        |> put_req_header("x-slack-signature", "v0=invalid")
        |> post("/api/slack/commands", %{"text" => "help", "team_id" => "T123"})

      assert json_response(conn, 401)["error"] == "Invalid signature"

      Application.delete_env(:uptrack, :slack_signing_secret)
    end
  end
end
