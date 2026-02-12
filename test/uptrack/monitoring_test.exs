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

  describe "org-scoped queries" do
    import Uptrack.MonitoringFixtures

    test "get_organization_monitor!/2 returns monitor scoped to org" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      found = Monitoring.get_organization_monitor!(org.id, monitor.id)
      assert found.id == monitor.id
    end

    test "get_organization_monitor!/2 raises for wrong org" do
      monitor = monitor_fixture()
      {_other_user, other_org} = user_with_org_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Monitoring.get_organization_monitor!(other_org.id, monitor.id)
      end
    end

    test "list_active_monitors/1 returns only active monitors for org" do
      {user, org} = user_with_org_fixture()
      active = monitor_fixture(organization_id: org.id, user_id: user.id, status: "active")
      _paused = monitor_fixture(organization_id: org.id, user_id: user.id, status: "paused")

      result = Monitoring.list_active_monitors(org.id)
      assert length(result) == 1
      assert hd(result).id == active.id
    end

    test "get_all_active_monitors/0 returns active monitors across all orgs" do
      {user1, org1} = user_with_org_fixture()
      {user2, org2} = user_with_org_fixture()

      m1 = monitor_fixture(organization_id: org1.id, user_id: user1.id, status: "active")
      m2 = monitor_fixture(organization_id: org2.id, user_id: user2.id, status: "active")
      _paused = monitor_fixture(organization_id: org1.id, user_id: user1.id, status: "paused")

      result = Monitoring.get_all_active_monitors()
      ids = Enum.map(result, & &1.id)
      assert m1.id in ids
      assert m2.id in ids
    end
  end

  describe "monitor_checks" do
    import Uptrack.MonitoringFixtures

    test "create_monitor_check/1 creates a check record" do
      monitor = monitor_fixture()

      attrs = %{
        monitor_id: monitor.id,
        status: "up",
        response_time: 150,
        status_code: 200,
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:ok, check} = Monitoring.create_monitor_check(attrs)
      assert check.status == "up"
      assert check.response_time == 150
      assert check.status_code == 200
    end

    test "get_recent_checks/2 returns checks ordered by most recent first" do
      monitor = monitor_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _old} =
        Monitoring.create_monitor_check(%{
          monitor_id: monitor.id,
          status: "up",
          response_time: 100,
          checked_at: DateTime.add(now, -60, :second)
        })

      {:ok, latest} =
        Monitoring.create_monitor_check(%{
          monitor_id: monitor.id,
          status: "down",
          response_time: 0,
          checked_at: now
        })

      [first | _] = Monitoring.get_recent_checks(monitor.id, 10)
      assert first.id == latest.id
    end

    test "get_latest_check/1 returns nil when no checks exist" do
      monitor = monitor_fixture()
      assert is_nil(Monitoring.get_latest_check(monitor.id))
    end

    test "get_latest_check/1 returns most recent check" do
      monitor = monitor_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Monitoring.create_monitor_check(%{
        monitor_id: monitor.id,
        status: "up",
        response_time: 100,
        checked_at: DateTime.add(now, -60, :second)
      })

      {:ok, latest} =
        Monitoring.create_monitor_check(%{
          monitor_id: monitor.id,
          status: "down",
          response_time: 0,
          checked_at: now
        })

      assert Monitoring.get_latest_check(monitor.id).id == latest.id
    end
  end

  describe "uptime_percentage" do
    import Uptrack.MonitoringFixtures

    test "returns 100.0 when no checks exist" do
      monitor = monitor_fixture()
      assert Monitoring.get_uptime_percentage(monitor.id) == 100.0
    end

    test "calculates percentage from check records" do
      monitor = monitor_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 3 up, 1 down = 75%
      for i <- 1..3 do
        Monitoring.create_monitor_check(%{
          monitor_id: monitor.id,
          status: "up",
          response_time: 100,
          checked_at: DateTime.add(now, -i * 60, :second)
        })
      end

      Monitoring.create_monitor_check(%{
        monitor_id: monitor.id,
        status: "down",
        response_time: 0,
        checked_at: DateTime.add(now, -240, :second)
      })

      assert Monitoring.get_uptime_percentage(monitor.id) == 75.0
    end
  end

  describe "incidents" do
    import Uptrack.MonitoringFixtures

    test "create_incident/1 creates an ongoing incident" do
      monitor = monitor_fixture()

      attrs = %{
        monitor_id: monitor.id,
        organization_id: monitor.organization_id,
        cause: "Connection timeout"
      }

      assert {:ok, incident} = Monitoring.create_incident(attrs)
      assert incident.status == "ongoing"
      assert incident.cause == "Connection timeout"
      assert incident.started_at
    end

    test "resolve_incident/1 sets resolved status and calculates duration" do
      monitor = monitor_fixture()

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: monitor.organization_id,
          cause: "Server error"
        })

      assert {:ok, resolved} = Monitoring.resolve_incident(incident)
      assert resolved.status == "resolved"
      assert resolved.resolved_at
      assert resolved.duration >= 0
    end

    test "get_ongoing_incident/1 returns ongoing incident for monitor" do
      monitor = monitor_fixture()

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: monitor.organization_id,
          cause: "Down"
        })

      found = Monitoring.get_ongoing_incident(monitor.id)
      assert found.id == incident.id
    end

    test "get_ongoing_incident/1 returns nil when no ongoing incident" do
      monitor = monitor_fixture()
      assert is_nil(Monitoring.get_ongoing_incident(monitor.id))
    end

    test "get_ongoing_incident/1 does not return resolved incidents" do
      monitor = monitor_fixture()

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: monitor.organization_id,
          cause: "Down"
        })

      Monitoring.resolve_incident(incident)

      assert is_nil(Monitoring.get_ongoing_incident(monitor.id))
    end

    test "list_recent_incidents/2 returns incidents scoped to organization" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, _incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Error"
        })

      # Different org should not see this incident
      {_other_user, other_org} = user_with_org_fixture()

      assert length(Monitoring.list_recent_incidents(org.id)) == 1
      assert Monitoring.list_recent_incidents(other_org.id) == []
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
