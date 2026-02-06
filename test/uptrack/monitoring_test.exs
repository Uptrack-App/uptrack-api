defmodule Uptrack.MonitoringTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring

  describe "monitors" do
    alias Uptrack.Monitoring.Monitor

    import Uptrack.MonitoringFixtures

    @invalid_attrs %{
      timeout: nil,
      name: nil,
      status: nil,
      description: nil,
      url: nil,
      monitor_type: nil,
      interval: nil,
      alert_contacts: nil,
      settings: nil,
      organization_id: nil,
      user_id: nil
    }

    test "list_monitors/1 returns monitors for organization" do
      monitor = monitor_fixture()
      assert Monitoring.list_monitors(monitor.organization_id) == [monitor]
    end

    test "get_monitor!/1 returns the monitor with given id" do
      monitor = monitor_fixture()
      assert Monitoring.get_monitor!(monitor.id) == monitor
    end

    test "create_monitor/1 with valid data creates a monitor" do
      {user, org} = user_with_org_fixture()

      valid_attrs = %{
        timeout: 30,
        name: "Test Monitor",
        status: "active",
        description: "Test description",
        url: "https://example.com",
        monitor_type: "http",
        interval: 300,
        alert_contacts: [],
        settings: %{},
        organization_id: org.id,
        user_id: user.id
      }

      assert {:ok, %Monitor{} = monitor} = Monitoring.create_monitor(valid_attrs)
      assert monitor.timeout == 30
      assert monitor.name == "Test Monitor"
      assert monitor.status == "active"
      assert monitor.description == "Test description"
      assert monitor.url == "https://example.com"
      assert monitor.monitor_type == "http"
      assert monitor.interval == 300
      assert monitor.alert_contacts == []
      assert monitor.settings == %{}
      assert monitor.organization_id == org.id
      assert monitor.user_id == user.id
    end

    test "create_monitor/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Monitoring.create_monitor(@invalid_attrs)
    end

    test "update_monitor/2 with valid data updates the monitor" do
      monitor = monitor_fixture()

      update_attrs = %{
        timeout: 60,
        name: "Updated Monitor",
        status: "paused",
        description: "Updated description",
        url: "https://updated.example.com",
        monitor_type: "https",
        interval: 600
      }

      assert {:ok, %Monitor{} = monitor} = Monitoring.update_monitor(monitor, update_attrs)
      assert monitor.timeout == 60
      assert monitor.name == "Updated Monitor"
      assert monitor.status == "paused"
      assert monitor.description == "Updated description"
      assert monitor.url == "https://updated.example.com"
      assert monitor.monitor_type == "https"
      assert monitor.interval == 600
    end

    test "update_monitor/2 with invalid data returns error changeset" do
      monitor = monitor_fixture()
      assert {:error, %Ecto.Changeset{}} = Monitoring.update_monitor(monitor, @invalid_attrs)
      assert monitor == Monitoring.get_monitor!(monitor.id)
    end

    test "delete_monitor/1 deletes the monitor" do
      monitor = monitor_fixture()
      assert {:ok, %Monitor{}} = Monitoring.delete_monitor(monitor)
      assert_raise Ecto.NoResultsError, fn -> Monitoring.get_monitor!(monitor.id) end
    end

    test "change_monitor/1 returns a monitor changeset" do
      monitor = monitor_fixture()
      assert %Ecto.Changeset{} = Monitoring.change_monitor(monitor)
    end
  end

  describe "status_page_subscribers" do
    alias Uptrack.Monitoring.StatusPageSubscriber

    import Uptrack.MonitoringFixtures

    test "subscribe_to_status_page/2 creates a subscriber" do
      status_page = status_page_fixture()

      assert {:ok, %StatusPageSubscriber{} = subscriber} =
               Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      assert subscriber.email == "test@example.com"
      assert subscriber.status_page_id == status_page.id
      assert subscriber.verified == false
      assert subscriber.verification_token != nil
      assert subscriber.unsubscribe_token != nil
    end

    test "subscribe_to_status_page/2 prevents duplicate emails" do
      status_page = status_page_fixture()

      {:ok, _} = Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      assert {:error, changeset} =
               Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      assert "already subscribed to this status page" in errors_on(changeset).status_page_id
    end

    test "verify_subscriber/1 marks subscriber as verified" do
      status_page = status_page_fixture()
      {:ok, subscriber} = Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      assert {:ok, verified_subscriber} = Monitoring.verify_subscriber(subscriber)
      assert verified_subscriber.verified == true
      assert verified_subscriber.subscribed_at != nil
    end

    test "unsubscribe/1 removes the subscriber" do
      status_page = status_page_fixture()
      {:ok, subscriber} = Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      assert {:ok, _} = Monitoring.unsubscribe(subscriber)
      assert Monitoring.get_subscriber_by_unsubscribe_token(subscriber.unsubscribe_token) == nil
    end

    test "get_subscriber_by_verification_token/1 finds subscriber" do
      status_page = status_page_fixture()
      {:ok, subscriber} = Monitoring.subscribe_to_status_page(status_page.id, "test@example.com")

      found = Monitoring.get_subscriber_by_verification_token(subscriber.verification_token)
      assert found.id == subscriber.id
    end
  end
end
