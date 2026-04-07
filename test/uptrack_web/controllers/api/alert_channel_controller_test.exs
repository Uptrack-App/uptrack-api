defmodule UptrackWeb.Api.AlertChannelControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/alert-channels" do
    test "lists alert channels", %{conn: conn, user: user, org: org} do
      _ch = alert_channel_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, "/api/alert-channels")

      response = json_response(conn, 200)
      assert [channel] = response["data"]
      assert channel["name"]
      assert channel["type"]
    end

    test "does not return channels from other orgs", %{conn: conn} do
      _other = alert_channel_fixture()

      conn = get(conn, "/api/alert-channels")

      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "POST /api/alert-channels" do
    test "creates an email alert channel on free plan", %{conn: conn} do
      conn =
        post(conn, "/api/alert-channels", %{
          "name" => "Email Alerts",
          "type" => "email",
          "config" => %{"email" => "alerts@example.com"}
        })

      response = json_response(conn, 201)
      assert response["data"]["name"] == "Email Alerts"
      assert response["data"]["type"] == "email"
    end

    test "creates a slack channel on pro plan", %{conn: conn, org: org} do
      Uptrack.Organizations.update_organization(org, %{plan: "pro"})

      conn =
        post(conn, "/api/alert-channels", %{
          "name" => "Slack Prod",
          "type" => "slack",
          "config" => %{"webhook_url" => "https://hooks.slack.com/test"}
        })

      response = json_response(conn, 201)
      assert response["data"]["type"] == "slack"
    end

    test "rejects unsupported channel types", %{conn: conn} do
      conn =
        post(conn, "/api/alert-channels", %{
          "name" => "Webhook",
          "type" => "webhook",
          "config" => %{"url" => "https://example.com/webhook"}
        })

      assert %{"error" => %{"message" => msg}} = json_response(conn, 402)
      assert msg =~ "not a supported alert channel type"
    end
  end

  describe "DELETE /api/alert-channels/:id" do
    test "deletes own channel", %{conn: conn, user: user, org: org} do
      ch = alert_channel_fixture(organization_id: org.id, user_id: user.id)

      conn = delete(conn, "/api/alert-channels/#{ch.id}")

      assert conn.status == 204
    end

    test "returns 404 for other org's channel", %{conn: conn} do
      other = alert_channel_fixture()

      conn = delete(conn, "/api/alert-channels/#{other.id}")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/alert-channels/:id" do
    test "returns a specific alert channel", %{conn: conn, user: user, org: org} do
      ch = alert_channel_fixture(organization_id: org.id, user_id: user.id)

      conn = get(conn, "/api/alert-channels/#{ch.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == ch.id
      assert response["data"]["name"] == ch.name
    end

    test "returns 404 for other org's channel", %{conn: conn} do
      other = alert_channel_fixture()

      conn = get(conn, "/api/alert-channels/#{other.id}")

      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent channel", %{conn: conn} do
      conn = get(conn, "/api/alert-channels/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/alert-channels/:id" do
    test "updates an alert channel", %{conn: conn, user: user, org: org} do
      ch = alert_channel_fixture(organization_id: org.id, user_id: user.id)

      conn = patch(conn, "/api/alert-channels/#{ch.id}", %{"name" => "Updated Channel"})

      response = json_response(conn, 200)
      assert response["data"]["name"] == "Updated Channel"
    end

    test "returns 404 for other org's channel", %{conn: conn} do
      other = alert_channel_fixture()

      conn = patch(conn, "/api/alert-channels/#{other.id}", %{"name" => "Hacked"})

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/alert-channels/:id/test" do
    test "returns 404 for other org's channel", %{conn: conn} do
      other = alert_channel_fixture()

      conn = post(conn, "/api/alert-channels/#{other.id}/test")

      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent channel", %{conn: conn} do
      conn = post(conn, "/api/alert-channels/#{Ecto.UUID.generate()}/test")
      assert json_response(conn, 404)
    end
  end
end
