defmodule UptrackWeb.Api.IncidentController do
  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  action_fallback UptrackWeb.Api.FallbackController

  def index(conn, params) do
    org = conn.assigns.current_organization

    incidents =
      case params["status"] do
        "ongoing" -> Monitoring.list_ongoing_incidents(org.id)
        _ -> Monitoring.list_incidents(org.id)
      end

    render(conn, :index, incidents: incidents)
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    incident = Monitoring.get_incident_with_updates!(id)

    if incident.organization_id == org.id do
      render(conn, :show, incident: incident)
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def create(conn, %{"monitor_id" => monitor_id} = params) do
    org = conn.assigns.current_organization

    monitor = Monitoring.get_organization_monitor(org.id, monitor_id)

    if monitor do
      attrs = %{
        "monitor_id" => monitor_id,
        "organization_id" => org.id,
        "cause" => params["cause"],
        "started_at" => DateTime.utc_now() |> DateTime.truncate(:second),
        "status" => "ongoing"
      }

      case Monitoring.create_incident(attrs) do
        {:ok, incident} ->
          incident = Monitoring.get_incident_with_updates!(incident.id)

          conn
          |> put_status(:created)
          |> render(:show, incident: incident)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  end

  def update(conn, %{"id" => id} = params) do
    org = conn.assigns.current_organization

    incident = Monitoring.get_incident!(id)

    if incident.organization_id == org.id do
      result =
        if params["status"] == "resolved" do
          Monitoring.resolve_incident(incident, Map.take(params, ["cause"]))
        else
          incident
          |> Uptrack.Monitoring.Incident.changeset(Map.take(params, ["cause", "status"]))
          |> Uptrack.AppRepo.update()
        end

      case result do
        {:ok, updated} ->
          updated = Monitoring.get_incident_with_updates!(updated.id)
          render(conn, :show, incident: updated)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def acknowledge(conn, %{"incident_id" => incident_id}) do
    org = conn.assigns.current_organization
    user = conn.assigns.current_user

    case Monitoring.get_incident(incident_id) do
      nil ->
        {:error, :not_found}

      incident ->
        if incident.organization_id != org.id do
          {:error, :not_found}
        else
          case Monitoring.acknowledge_incident(incident, user.id) do
            {:ok, updated} ->
              updated = Monitoring.get_incident_with_updates!(updated.id)
              render(conn, :show, incident: updated)

            {:error, changeset} ->
              {:error, changeset}
          end
        end
    end
  end

  def create_update(conn, %{"incident_id" => incident_id} = params) do
    org = conn.assigns.current_organization
    user = conn.assigns.current_user

    incident = Monitoring.get_incident!(incident_id)

    if incident.organization_id == org.id do
      attrs = %{
        "incident_id" => incident_id,
        "user_id" => user.id,
        "title" => params["title"],
        "description" => params["description"],
        "status" => params["status"] || "investigating",
        "posted_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Monitoring.create_incident_update(attrs) do
        {:ok, _update} ->
          if params["status"] == "resolved" && incident.status != "resolved" do
            Monitoring.resolve_incident(incident)
          end

          incident = Monitoring.get_incident_with_updates!(incident_id)
          render(conn, :show, incident: incident)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
