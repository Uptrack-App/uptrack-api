defmodule Uptrack.Alerting.IncidentReminder do
  @moduledoc """
  Decides when a "still down" reminder is due for an open incident and
  enqueues the dispatch.

  ## Pure / Impure separation

  - `due?/3` is pure: takes incident, monitor, and current time, returns
    one of `:disabled`, `:not_due`, `:resolved`, `:acknowledged`, or
    `{:due, snapped_last_reminder_at}`.
  - `maybe_send/2` is the impure boundary: loads the incident, calls
    `due?/3`, dispatches alerts, and updates the incident.

  ## Snap-to-grid scheduling

  Reminders are anchored to `incident.started_at`. The new
  `last_reminder_sent_at` is always a multiple of `interval_minutes`
  from `started_at`, so check-loop jitter never accumulates drift.

  Even if multiple intervals were "missed" (e.g. the worker was paused),
  we send exactly **one** reminder and snap forward to the most recent
  multiple — we do not catch up by spamming.
  """

  alias Uptrack.Alerting
  alias Uptrack.Maintenance
  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Incident, Monitor}
  require Logger

  @type due_result ::
          :disabled
          | :resolved
          | :not_due
          | :acknowledged
          | {:due, DateTime.t()}

  @doc """
  Pure decision function. Returns whether a reminder is due and, if so,
  the snapped `last_reminder_sent_at` value to persist.
  """
  @spec due?(Incident.t(), Monitor.t(), DateTime.t()) :: due_result
  def due?(_incident, %Monitor{reminder_interval_minutes: nil}, _now), do: :disabled

  def due?(%Incident{status: status}, _monitor, _now) when status != "ongoing", do: :resolved

  def due?(%Incident{acknowledged_at: acknowledged_at}, _monitor, _now)
      when not is_nil(acknowledged_at),
      do: :acknowledged

  def due?(%Incident{} = incident, %Monitor{reminder_interval_minutes: minutes}, now)
      when is_integer(minutes) do
    interval_seconds = minutes * 60
    anchor = incident.last_reminder_sent_at || incident.started_at
    next_due_at = DateTime.add(anchor, interval_seconds, :second)

    if DateTime.compare(now, next_due_at) == :lt do
      :not_due
    else
      # Snap to the most recent multiple of interval from started_at.
      # Counts how many full intervals have elapsed since started_at,
      # then re-anchors there. Prevents drift across reminders.
      elapsed = DateTime.diff(now, incident.started_at)
      multiples = div(elapsed, interval_seconds)
      snapped = DateTime.add(incident.started_at, multiples * interval_seconds, :second)
      {:due, snapped}
    end
  end

  @doc """
  Impure boundary. Loads the incident by id, decides if a reminder is
  due, and if so dispatches alerts and updates the incident.

  Designed to be called from inside a `Task.Supervisor` task — never
  blocks the caller, never raises (all errors are logged).
  """
  @spec maybe_send(binary(), Monitor.t()) :: due_result | :maintenance | {:error, term()}
  def maybe_send(incident_id, %Monitor{} = monitor) do
    incident = Monitoring.get_incident!(incident_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case due?(incident, monitor, now) do
      {:due, snapped} ->
        if Maintenance.under_maintenance?(monitor.id, monitor.organization_id) do
          Logger.info(
            "Reminder skipped for incident #{incident.id} — monitor under maintenance"
          )

          :maintenance
        else
          Logger.info(
            "Reminder due for incident #{incident.id} on monitor #{monitor.name} (count=#{incident.reminder_count + 1})"
          )

          Alerting.send_incident_reminder(incident, monitor)

          Monitoring.update_incident(incident, %{
            last_reminder_sent_at: snapped,
            reminder_count: incident.reminder_count + 1
          })

          {:due, snapped}
        end

      other ->
        Logger.debug("Reminder skipped for incident #{incident.id}: #{inspect(other)}")
        other
    end
  rescue
    e ->
      Logger.error(
        "IncidentReminder.maybe_send failed for incident #{incident_id}: #{Exception.message(e)}"
      )

      {:error, Exception.message(e)}
  end

end
