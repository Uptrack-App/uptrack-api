defmodule Uptrack.Escalation.EscalationWorker do
  @moduledoc """
  Oban worker that fires the next step in an escalation chain.
  Scheduled with a delay based on the step's delay_minutes.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Uptrack.Escalation
  alias Uptrack.Monitoring
  alias Uptrack.Alerting.AlertDeliveryWorker
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "incident_id" => incident_id,
      "policy_id" => policy_id,
      "step_order" => step_order,
      "monitor_id" => monitor_id
    } = args

    # Check if incident is still ongoing (not resolved or acknowledged)
    incident = Monitoring.get_incident(incident_id)

    cond do
      is_nil(incident) ->
        Logger.info("Escalation: incident #{incident_id} no longer exists, cancelling")
        :ok

      incident.status != "ongoing" ->
        Logger.info("Escalation: incident #{incident_id} is #{incident.status}, cancelling")
        :ok

      incident.acknowledged_at != nil ->
        Logger.info("Escalation: incident #{incident_id} acknowledged, cancelling escalation")
        :ok

      true ->
        # Fire alerts for this step
        steps = Escalation.get_steps_for_order(policy_id, step_order)
        monitor = Monitoring.get_monitor!(monitor_id)

        if monitor do
          Enum.each(steps, fn step ->
            channel = step.alert_channel

            if channel && channel.is_active do
              Logger.info("Escalation step #{step_order}: sending via #{channel.name} for incident #{incident_id}")

              %{
                channel_id: channel.id,
                incident_id: incident_id,
                monitor_id: monitor_id,
                event_type: "incident_created"
              }
              |> AlertDeliveryWorker.new()
              |> Oban.insert()
            end
          end)

          # Schedule next step if exists
          max_order = Escalation.max_step_order(policy_id)

          if step_order < max_order do
            next_step_order = step_order + 1
            next_steps = Escalation.get_steps_for_order(policy_id, next_step_order)
            next_delay = next_steps |> List.first() |> then(fn s -> if s, do: s.delay_minutes, else: 5 end)

            %{
              incident_id: incident_id,
              policy_id: policy_id,
              step_order: next_step_order,
              monitor_id: monitor_id
            }
            |> __MODULE__.new(scheduled_at: DateTime.add(DateTime.utc_now(), next_delay * 60, :second))
            |> Oban.insert()

            Logger.info("Escalation: scheduled step #{next_step_order} in #{next_delay}min for incident #{incident_id}")
          end
        end

        :ok
    end
  end
end
