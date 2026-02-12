defmodule Uptrack.Alerting.DeliveryTrackerTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.DeliveryTracker

  setup do
    org = Uptrack.MonitoringFixtures.organization_fixture()
    {:ok, org: org}
  end

  describe "record_success/1" do
    test "records a successful delivery", %{org: org} do
      {:ok, delivery} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })

      assert delivery.status == "delivered"
      assert delivery.channel_type == "email"
      assert delivery.event_type == "incident_created"
      assert delivery.organization_id == org.id
    end
  end

  describe "record_failure/2" do
    test "records a failed delivery with error message", %{org: org} do
      {:ok, delivery} =
        DeliveryTracker.record_failure(
          %{
            channel_type: "slack",
            event_type: "incident_created",
            organization_id: org.id
          },
          "Connection timeout"
        )

      assert delivery.status == "failed"
      assert delivery.error_message == "Connection timeout"
    end
  end

  describe "record_skipped/2" do
    test "records a skipped delivery with reason", %{org: org} do
      {:ok, delivery} =
        DeliveryTracker.record_skipped(
          %{
            channel_type: "telegram",
            event_type: "incident_resolved",
            organization_id: org.id
          },
          "User disabled notifications"
        )

      assert delivery.status == "skipped"
      assert delivery.error_message == "User disabled notifications"
    end
  end

  describe "list_deliveries/2" do
    test "returns deliveries for organization", %{org: org} do
      {:ok, _d1} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })

      {:ok, _d2} =
        DeliveryTracker.record_failure(
          %{
            channel_type: "slack",
            event_type: "incident_created",
            organization_id: org.id
          },
          "error"
        )

      deliveries = DeliveryTracker.list_deliveries(org.id)

      assert length(deliveries) == 2
      channel_types = Enum.map(deliveries, & &1.channel_type) |> Enum.sort()
      assert channel_types == ["email", "slack"]
    end

    test "filters by status", %{org: org} do
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
          "error"
        )

      deliveries = DeliveryTracker.list_deliveries(org.id, status: "delivered")
      assert length(deliveries) == 1
      assert hd(deliveries).status == "delivered"
    end

    test "respects limit", %{org: org} do
      for _ <- 1..5 do
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: org.id
        })
      end

      deliveries = DeliveryTracker.list_deliveries(org.id, limit: 3)
      assert length(deliveries) == 3
    end

    test "does not return deliveries from other orgs", %{org: org} do
      other_org = Uptrack.MonitoringFixtures.organization_fixture()

      {:ok, _} =
        DeliveryTracker.record_success(%{
          channel_type: "email",
          event_type: "incident_created",
          organization_id: other_org.id
        })

      deliveries = DeliveryTracker.list_deliveries(org.id)
      assert deliveries == []
    end
  end

  describe "get_delivery_stats/2" do
    test "returns counts grouped by status", %{org: org} do
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
          "error"
        )

      stats = DeliveryTracker.get_delivery_stats(org.id)

      assert stats["delivered"] == 2
      assert stats["failed"] == 1
    end

    test "returns empty map when no deliveries", %{org: org} do
      stats = DeliveryTracker.get_delivery_stats(org.id)
      assert stats == %{}
    end
  end
end
