defmodule UptrackWeb.Api.MaintenanceWindowJSON do
  alias Uptrack.Maintenance.MaintenanceWindow

  def index(%{maintenance_windows: windows}) do
    %{data: Enum.map(windows, &data/1)}
  end

  def show(%{maintenance_window: window}) do
    %{data: data(window)}
  end

  defp data(%MaintenanceWindow{} = w) do
    %{
      id: w.id,
      title: w.title,
      description: w.description,
      start_time: w.start_time,
      end_time: w.end_time,
      recurrence: w.recurrence,
      status: w.status,
      monitor_id: w.monitor_id,
      organization_id: w.organization_id,
      inserted_at: w.inserted_at,
      updated_at: w.updated_at
    }
  end
end
