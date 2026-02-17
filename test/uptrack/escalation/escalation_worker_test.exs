defmodule Uptrack.Escalation.EscalationWorkerTest do
  use Uptrack.DataCase

  alias Uptrack.Escalation
  alias Uptrack.Escalation.EscalationWorker
  alias Uptrack.Monitoring

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  # Build Oban.Job struct for testing perform/1 directly
  defp build_job(args) do
    %Oban.Job{args: stringify_keys(args)}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  setup do
    {user, org} = user_with_org_fixture()
    monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

    channel =
      alert_channel_fixture(organization_id: org.id, user_id: user.id)

    {:ok, policy} =
      Escalation.create_policy(%{
        name: "Test Escalation",
        description: "test",
        organization_id: org.id
      })

    {:ok, _step} =
      Escalation.add_step(%{
        escalation_policy_id: policy.id,
        alert_channel_id: channel.id,
        step_order: 1,
        delay_minutes: 5
      })

    {:ok, _step2} =
      Escalation.add_step(%{
        escalation_policy_id: policy.id,
        alert_channel_id: channel.id,
        step_order: 2,
        delay_minutes: 10
      })

    {:ok, incident} =
      Monitoring.create_incident(%{
        monitor_id: monitor.id,
        organization_id: org.id,
        cause: "Connection timeout"
      })

    %{
      org: org,
      user: user,
      monitor: monitor,
      channel: channel,
      policy: policy,
      incident: incident
    }
  end

  describe "perform/1" do
    test "executes successfully for ongoing incident", ctx do
      job = build_job(%{
        incident_id: ctx.incident.id,
        policy_id: ctx.policy.id,
        step_order: 1,
        monitor_id: ctx.monitor.id
      })

      assert :ok = EscalationWorker.perform(job)
    end

    test "skips when incident is resolved", ctx do
      {:ok, _} = Monitoring.resolve_incident(ctx.incident)

      job = build_job(%{
        incident_id: ctx.incident.id,
        policy_id: ctx.policy.id,
        step_order: 1,
        monitor_id: ctx.monitor.id
      })

      assert :ok = EscalationWorker.perform(job)
    end

    test "skips when incident is acknowledged", ctx do
      {:ok, _} = Monitoring.acknowledge_incident(ctx.incident, ctx.user.id)

      job = build_job(%{
        incident_id: ctx.incident.id,
        policy_id: ctx.policy.id,
        step_order: 1,
        monitor_id: ctx.monitor.id
      })

      assert :ok = EscalationWorker.perform(job)
    end

    test "skips when incident does not exist", ctx do
      job = build_job(%{
        incident_id: Uniq.UUID.uuid7(),
        policy_id: ctx.policy.id,
        step_order: 1,
        monitor_id: ctx.monitor.id
      })

      assert :ok = EscalationWorker.perform(job)
    end

    test "executes last step without error", ctx do
      job = build_job(%{
        incident_id: ctx.incident.id,
        policy_id: ctx.policy.id,
        step_order: 2,
        monitor_id: ctx.monitor.id
      })

      assert :ok = EscalationWorker.perform(job)
    end
  end
end
