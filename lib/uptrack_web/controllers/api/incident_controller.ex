defmodule UptrackWeb.Api.IncidentController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Monitoring
  alias Uptrack.Teams

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

  def monitor_incidents(conn, %{"monitor_id" => monitor_id}) do
    org = conn.assigns.current_organization
    incidents = Monitoring.list_monitor_incidents(org.id, monitor_id)
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

  @doc """
  GET /api/incidents/:id/forensic

  Returns the forensic events for an incident, pulled from VictoriaLogs
  via `vl_trace_id`. Falls back gracefully when forensic data is
  unavailable (pre-retention incident, missing trace_id, or VL down).
  """
  def forensic(conn, %{"incident_id" => incident_id}) do
    org = conn.assigns.current_organization
    incident = Monitoring.get_incident!(incident_id)
    retention_cutoff = plan_retention_cutoff(org.plan)

    cond do
      incident.organization_id != org.id ->
        {:error, :not_found}

      is_nil(incident.vl_trace_id) ->
        json(conn, %{
          events: [],
          forensic_available: false,
          reason: "predates_forensic_tracking"
        })

      DateTime.compare(incident.started_at, retention_cutoff) == :lt ->
        json(conn, %{
          events: [],
          forensic_available: false,
          reason: "beyond_plan_retention",
          plan: org.plan,
          retention_days: Billing.plan_limit(org.plan, :retention_days)
        })

      true ->
        case Uptrack.Failures.VlClient.fetch_by_trace_id(
               incident.monitor_id,
               incident.vl_trace_id
             ) do
          {:ok, events} ->
            json(conn, %{events: events, forensic_available: true})

          {:error, :all_urls_unreachable} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{events: [], forensic_available: false, reason: "vl_unreachable"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              events: [],
              forensic_available: false,
              reason: "vl_error",
              detail: inspect(reason)
            })
        end
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp plan_retention_cutoff(plan) do
    days = Billing.plan_limit(plan, :retention_days) || 30
    DateTime.add(DateTime.utc_now(), -days * 86400, :second)
  end

  def create(conn, %{"monitor_id" => monitor_id} = params) do
    _user = conn.assigns.current_user
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
          Teams.log_action_from_conn(conn, "incident.created", "incident", incident.id,
            metadata: %{monitor_id: monitor_id, cause: params["cause"]}
          )

          incident = Monitoring.get_incident_with_updates!(incident.id)

          conn
          |> put_status(:created)
          |> render(:show, incident: incident)

        {:error, :already_ongoing} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "An ongoing incident already exists for this monitor"})

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  end

  def update(conn, %{"id" => id} = params) do
    _user = conn.assigns.current_user
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
          action = if params["status"] == "resolved", do: "incident.resolved", else: "incident.updated"

          Teams.log_action_from_conn(conn, action, "incident", updated.id)

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
              Teams.log_action_from_conn(conn, "incident.acknowledged", "incident", updated.id)

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
