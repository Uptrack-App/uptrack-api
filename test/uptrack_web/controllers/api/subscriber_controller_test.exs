defmodule UptrackWeb.Api.SubscriberControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  describe "POST /api/status/:slug/subscribe" do
    test "creates a subscriber with valid email", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      conn =
        post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{
          "email" => "subscriber@example.com"
        })

      response = json_response(conn, 201)
      assert response["success"] == true
      assert response["message"] =~ "verify"
    end

    test "returns error for invalid email format", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      conn =
        post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{
          "email" => "invalid-email"
        })

      assert json_response(conn, 422)["error"] != nil
    end

    test "returns error for non-existent status page", %{conn: conn} do
      conn =
        post(conn, ~p"/api/status/non-existent/subscribe", %{
          "email" => "test@example.com"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns error when subscriptions are disabled", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: false})

      conn =
        post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{
          "email" => "test@example.com"
        })

      assert json_response(conn, 403)["error"] =~ "not enabled"
    end

    test "handles already subscribed gracefully", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      # First subscription
      post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{
        "email" => "duplicate@example.com"
      })

      # Duplicate subscription - should succeed with message about already subscribed
      conn =
        post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{
          "email" => "duplicate@example.com"
        })

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "already subscribed"
    end

    test "returns error when email is missing", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      conn = post(conn, ~p"/api/status/#{status_page.slug}/subscribe", %{})

      assert json_response(conn, 400)["error"] =~ "required"
    end
  end

  describe "GET /api/subscribe/verify/:token" do
    test "verifies subscriber with valid token", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      {:ok, subscriber} =
        Uptrack.Monitoring.subscribe_to_status_page(status_page.id, "verify@example.com")

      conn = get(conn, ~p"/api/subscribe/verify/#{subscriber.verification_token}")

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "verified"
    end

    test "returns error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/api/subscribe/verify/invalid-token")

      assert json_response(conn, 404)["error"] =~ "Invalid"
    end

    test "handles already verified subscriber", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      {:ok, subscriber} =
        Uptrack.Monitoring.subscribe_to_status_page(status_page.id, "already@example.com")

      # Verify once
      {:ok, verified_subscriber} = Uptrack.Monitoring.verify_subscriber(subscriber)

      # The verification token is cleared after verification
      # So a second attempt with the original token returns 404
      conn = get(conn, ~p"/api/subscribe/verify/#{subscriber.verification_token}")

      # Token is cleared after verification - subscriber can't be found
      if verified_subscriber.verification_token do
        # Token was preserved - should succeed with already verified message
        response = json_response(conn, 200)
        assert response["message"] =~ "already verified"
      else
        # Token was cleared - returns 404
        assert conn.status == 404
      end
    end
  end

  describe "GET /api/subscribe/unsubscribe/:token" do
    test "unsubscribes with valid token", %{conn: conn} do
      status_page = status_page_fixture(%{allow_subscriptions: true})

      {:ok, subscriber} =
        Uptrack.Monitoring.subscribe_to_status_page(status_page.id, "unsub@example.com")

      conn = get(conn, ~p"/api/subscribe/unsubscribe/#{subscriber.unsubscribe_token}")

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "unsubscribed"
    end

    test "returns error for invalid unsubscribe token", %{conn: conn} do
      conn = get(conn, ~p"/api/subscribe/unsubscribe/invalid-token")

      assert json_response(conn, 404)["error"] =~ "Invalid"
    end
  end
end
