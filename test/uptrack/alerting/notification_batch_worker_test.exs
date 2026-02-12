defmodule Uptrack.Alerting.NotificationBatchWorkerTest do
  use Uptrack.DataCase

  import Swoosh.TestAssertions
  import Uptrack.MonitoringFixtures

  alias Uptrack.AppRepo
  alias Uptrack.Alerting.{NotificationBatchWorker, PendingNotification}

  @moduletag :capture_log

  describe "perform/1" do
    test "sends digest email for pending notifications" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, incident} =
        Uptrack.Monitoring.create_incident(%{
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "ongoing",
          organization_id: org.id,
          monitor_id: monitor.id
        })

      # Create pending notification
      {:ok, _pn} =
        %PendingNotification{}
        |> PendingNotification.changeset(%{
          event_type: "incident_created",
          recipient_email: user.email,
          incident_id: incident.id,
          monitor_id: monitor.id,
          user_id: user.id,
          organization_id: org.id
        })
        |> AppRepo.insert()

      # Run the batch worker
      assert :ok = NotificationBatchWorker.perform(%Oban.Job{})

      # Verify digest email was sent
      assert_email_sent(fn email ->
        assert email.subject =~ "Uptrack Digest"
        assert email.subject =~ "1 incident"
      end)

      # Verify pending notification was marked as delivered
      pending = AppRepo.all(PendingNotification)
      assert Enum.all?(pending, & &1.delivered)
    end

    test "does nothing when no pending notifications" do
      assert :ok = NotificationBatchWorker.perform(%Oban.Job{})
      assert_no_email_sent()
    end

    test "groups notifications by user" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, incident1} =
        Uptrack.Monitoring.create_incident(%{
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "ongoing",
          organization_id: org.id,
          monitor_id: monitor.id
        })

      # Create two pending notifications for same user
      for event_type <- ["incident_created", "incident_resolved"] do
        %PendingNotification{}
        |> PendingNotification.changeset(%{
          event_type: event_type,
          recipient_email: user.email,
          incident_id: incident1.id,
          monitor_id: monitor.id,
          user_id: user.id,
          organization_id: org.id
        })
        |> AppRepo.insert!()
      end

      assert :ok = NotificationBatchWorker.perform(%Oban.Job{})

      # Should send one digest email (grouped by user)
      assert_email_sent(fn email ->
        assert email.subject =~ "1 incident"
        assert email.subject =~ "1 resolution"
      end)
    end

    test "skips already delivered notifications" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, incident} =
        Uptrack.Monitoring.create_incident(%{
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "ongoing",
          organization_id: org.id,
          monitor_id: monitor.id
        })

      # Create already-delivered notification
      %PendingNotification{}
      |> PendingNotification.changeset(%{
        event_type: "incident_created",
        recipient_email: user.email,
        incident_id: incident.id,
        monitor_id: monitor.id,
        user_id: user.id,
        organization_id: org.id
      })
      |> Ecto.Changeset.put_change(:delivered, true)
      |> AppRepo.insert!()

      assert :ok = NotificationBatchWorker.perform(%Oban.Job{})
      assert_no_email_sent()
    end
  end
end
