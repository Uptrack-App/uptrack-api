defmodule UptrackWeb.Api.NotificationDeliveryControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Alerting.DeliveryTracker

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/notification-deliveries" do
    test "returns empty list when no deliveries", %{conn: conn} do
      conn = get(conn, ~p"/api/notification-deliveries")
      response = json_response(conn, 200)

      assert response["notification_deliveries"] == []
    end

    test "returns deliveries for the organization", %{conn: conn, org: org} do
      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })

      {:ok, _} =
        DeliveryTracker.record_failure(
          %{
            channel_type: "slack",
            event_type: "incident_created",
            organization_id: org.id
          },
          "Connection refused"
        )

      conn = get(conn, ~p"/api/notification-deliveries")
      response = json_response(conn, 200)

      assert length(response["notification_deliveries"]) == 2

      statuses = Enum.map(response["notification_deliveries"], & &1["status"])
      assert "delivered" in statuses
      assert "failed" in statuses
    end

    test "filters by status", %{conn: conn, org: org} do
      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })

      {:ok, _} =
        DeliveryTracker.record_failure(
          %{
            channel_type: "slack",
            event_type: "incident_created",
            organization_id: org.id
          },
          "timeout"
        )

      conn = get(conn, ~p"/api/notification-deliveries?status=delivered")
      response = json_response(conn, 200)

      assert length(response["notification_deliveries"]) == 1
      assert hd(response["notification_deliveries"])["status"] == "delivered"
    end

    test "respects limit parameter", %{conn: conn, org: org} do
      for _ <- 1..5 do
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })
      end

      conn = get(conn, ~p"/api/notification-deliveries?limit=2")
      response = json_response(conn, 200)

      assert length(response["notification_deliveries"]) == 2
    end

    test "does not return deliveries from other organizations", %{conn: conn, org: _org} do
      # Create a delivery for a different org
      other_org = Uptrack.MonitoringFixtures.organization_fixture()

      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: other_org.id
        })

      conn = get(conn, ~p"/api/notification-deliveries")
      response = json_response(conn, 200)

      assert response["notification_deliveries"] == []
    end
  end

  describe "GET /api/notification-deliveries/stats" do
    test "returns empty stats when no deliveries", %{conn: conn} do
      conn = get(conn, ~p"/api/notification-deliveries/stats")
      response = json_response(conn, 200)

      assert response["stats"] == %{}
      assert response["period_days"] == 7
    end

    test "returns stats grouped by status", %{conn: conn, org: org} do
      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })

      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "slack",
          event_type: "incident_resolved",
          organization_id: org.id
        })

      {:ok, _} =
        DeliveryTracker.record_failure(
          %{
            channel_type: "discord",
            event_type: "incident_created",
            organization_id: org.id
          },
          "webhook error"
        )

      conn = get(conn, ~p"/api/notification-deliveries/stats")
      response = json_response(conn, 200)

      assert response["stats"]["delivered"] == 2
      assert response["stats"]["failed"] == 1
    end

    test "accepts custom days parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/notification-deliveries/stats?days=30")
      response = json_response(conn, 200)

      assert response["period_days"] == 30
    end
  end
end
