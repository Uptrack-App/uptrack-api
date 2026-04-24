defmodule Uptrack.Monitoring.Events do
  @moduledoc """
  Event broadcasting for real-time monitoring updates using Phoenix PubSub.
  """

  alias Uptrack.Monitoring.{Monitor, MonitorCheck, Incident}

  @doc """
  Broadcasts when a monitor check is completed.
  """
  def broadcast_check_completed(%MonitorCheck{} = check, %Monitor{} = monitor) do
    event_data = %{
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      status: check.status,
      response_time: check.response_time,
      checked_at: check.checked_at,
      error_message: check.error_message
    }

    # Broadcast to user-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:check_completed, event_data}
    )

    # Broadcast to monitor-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:check_completed, event_data}
    )
  end

  @doc """
  Broadcasts when an incident is created.
  """
  def broadcast_incident_created(%Incident{} = incident, %Monitor{} = monitor) do
    event_data = %{
      incident_id: incident.id,
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      started_at: incident.started_at,
      cause: incident.cause
    }

    # Broadcast to user-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:incident_created, event_data}
    )

    # Broadcast to monitor-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:incident_created, event_data}
    )
  end

  @doc """
  Broadcasts when an incident is updated in place (e.g. degradation upgraded to down).
  """
  def broadcast_incident_updated(%Incident{} = incident, %Monitor{} = monitor) do
    event_data = %{
      incident_id: incident.id,
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      cause: incident.cause,
      updated_at: incident.updated_at
    }

    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:incident_updated, event_data}
    )

    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:incident_updated, event_data}
    )
  end

  @doc """
  Broadcasts when an incident is resolved.
  """
  def broadcast_incident_resolved(%Incident{} = incident, %Monitor{} = monitor) do
    event_data = %{
      incident_id: incident.id,
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      resolved_at: incident.resolved_at,
      duration: incident.duration
    }

    # Broadcast to user-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:incident_resolved, event_data}
    )

    # Broadcast to monitor-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:incident_resolved, event_data}
    )
  end

  @doc """
  Broadcasts when a monitor enters or exits the FLAPPING state.
  Flap detection is handled by `Uptrack.Monitoring.FlapDetector`; this
  event lets the dashboard render a FLAPPING pill without polling.
  """
  def broadcast_monitor_flapping(%Monitor{} = monitor, flapping?) when is_boolean(flapping?) do
    event_data = %{
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      flapping: flapping?,
      observed_at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:monitor_flapping, event_data}
    )

    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:monitor_flapping, event_data}
    )
  end

  @doc """
  Broadcasts when a monitor status changes.
  """
  def broadcast_monitor_status_changed(%Monitor{} = monitor, old_status, new_status) do
    event_data = %{
      monitor_id: monitor.id,
      monitor_name: monitor.name,
      old_status: old_status,
      new_status: new_status,
      changed_at: DateTime.utc_now()
    }

    # Broadcast to user-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "user:#{monitor.user_id}",
      {:monitor_status_changed, event_data}
    )

    # Broadcast to monitor-specific channel
    Phoenix.PubSub.broadcast(
      Uptrack.PubSub,
      "monitor:#{monitor.id}",
      {:monitor_status_changed, event_data}
    )
  end

  @doc """
  Broadcasts dashboard stats updates.
  """
  def broadcast_dashboard_update(user_id, stats) do
    event_data = %{
      stats: stats,
      updated_at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Uptrack.PubSub, "user:#{user_id}", {:dashboard_update, event_data})
  end
end
