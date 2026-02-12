defmodule UptrackWeb.Api.IncidentJSON do
  alias Uptrack.Monitoring.{Incident, IncidentUpdate}

  def index(%{incidents: incidents}) do
    %{data: for(i <- incidents, do: incident_data(i))}
  end

  def show(%{incident: incident}) do
    %{data: incident_data(incident)}
  end

  defp incident_data(%Incident{} = i) do
    monitor_name =
      case i do
        %{monitor: %{name: name}} -> name
        _ -> nil
      end

    updates =
      case i do
        %{incident_updates: updates} when is_list(updates) ->
          for(u <- updates, do: incident_update_data(u))

        _ ->
          []
      end

    %{
      id: i.id,
      monitor_id: i.monitor_id,
      monitor_name: monitor_name,
      status: i.status,
      cause: i.cause,
      started_at: i.started_at,
      resolved_at: i.resolved_at,
      duration: i.duration,
      updates: updates,
      inserted_at: i.inserted_at
    }
  end

  defp incident_update_data(%IncidentUpdate{} = u) do
    %{
      id: u.id,
      status: u.status,
      title: u.title,
      description: u.description,
      posted_at: u.posted_at,
      user_id: u.user_id
    }
  end
end
