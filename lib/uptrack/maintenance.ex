defmodule Uptrack.Maintenance do
  @moduledoc """
  Context for maintenance window management.
  """

  import Ecto.Query
  alias Uptrack.AppRepo
  alias Uptrack.Maintenance.MaintenanceWindow

  def list_maintenance_windows(organization_id, opts \\ []) do
    query =
      from mw in MaintenanceWindow,
        where: mw.organization_id == ^organization_id,
        order_by: [desc: mw.start_time]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [mw], mw.status == ^status)
      end

    query =
      case Keyword.get(opts, :monitor_id) do
        nil -> query
        monitor_id -> where(query, [mw], mw.monitor_id == ^monitor_id)
      end

    AppRepo.all(query)
  end

  def get_maintenance_window(id) do
    AppRepo.get(MaintenanceWindow, id)
  end

  def get_organization_maintenance_window(organization_id, id) do
    AppRepo.get_by(MaintenanceWindow, id: id, organization_id: organization_id)
  end

  def create_maintenance_window(attrs) do
    %MaintenanceWindow{}
    |> MaintenanceWindow.changeset(attrs)
    |> AppRepo.insert()
  end

  def update_maintenance_window(%MaintenanceWindow{} = window, attrs) do
    window
    |> MaintenanceWindow.changeset(attrs)
    |> AppRepo.update()
  end

  def delete_maintenance_window(%MaintenanceWindow{} = window) do
    AppRepo.delete(window)
  end

  @doc """
  Checks if a monitor is currently under an active maintenance window.
  Returns the active window or nil.
  """
  def active_maintenance_window(monitor_id, organization_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(mw in MaintenanceWindow,
      where:
        mw.organization_id == ^organization_id and
          mw.status == "active" and
          mw.start_time <= ^now and
          mw.end_time >= ^now and
          (is_nil(mw.monitor_id) or mw.monitor_id == ^monitor_id),
      limit: 1
    )
    |> AppRepo.one()
  end

  @doc """
  Checks if a monitor is under maintenance (returns boolean).
  """
  def under_maintenance?(monitor_id, organization_id) do
    active_maintenance_window(monitor_id, organization_id) != nil
  end

  @doc """
  Activates scheduled windows whose start time has passed.
  Called by the MaintenanceWorker Oban job.
  """
  def activate_scheduled_windows do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(mw in MaintenanceWindow,
      where: mw.status == "scheduled" and mw.start_time <= ^now
    )
    |> AppRepo.update_all(set: [status: "active", updated_at: now])
  end

  @doc """
  Completes active windows whose end time has passed.
  Called by the MaintenanceWorker Oban job.
  """
  def complete_expired_windows do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(mw in MaintenanceWindow,
      where: mw.status == "active" and mw.end_time <= ^now
    )
    |> AppRepo.update_all(set: [status: "completed", updated_at: now])
  end

  @doc """
  Returns upcoming maintenance windows (within next 7 days) for status page display.
  """
  def upcoming_maintenance(organization_id, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    lookahead = Keyword.get(opts, :days, 7)
    future = DateTime.add(now, lookahead * 24 * 3600, :second)

    from(mw in MaintenanceWindow,
      where:
        mw.organization_id == ^organization_id and
          mw.status in ["scheduled", "active"] and
          mw.start_time <= ^future,
      order_by: [asc: mw.start_time]
    )
    |> AppRepo.all()
  end
end
