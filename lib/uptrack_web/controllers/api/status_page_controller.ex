defmodule UptrackWeb.Api.StatusPageController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Maintenance
  alias Uptrack.Monitoring
  alias Uptrack.Teams

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  GET /api/status/:slug/uptime — public endpoint, no auth required.
  Returns daily uptime data for all monitors on the status page (last 90 days).
  """
  def public_uptime(conn, %{"slug" => slug}) do
    alias Uptrack.Metrics.Reader
    alias Uptrack.Cache

    status_page = Monitoring.get_status_page_with_status!(slug)

    if status_page.is_public do
      result =
        Cache.fetch("status_uptime:#{slug}", [ttl: :timer.minutes(5)], fn ->
          now = DateTime.utc_now()
          start_time = DateTime.add(now, -90 * 86400, :second)

          monitor_ids = Enum.map(status_page.monitors, & &1.id)

          uptime_data =
            Enum.map(monitor_ids, fn monitor_id ->
              daily =
                case Reader.get_daily_uptime(monitor_id, start_time, now) do
                  {:ok, points} -> points
                  _ -> []
                end

              %{monitor_id: monitor_id, daily_uptime: daily}
            end)

          %{monitors: uptime_data, days: 90}
        end)

      json(conn, result)
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def public_regions(conn, %{"slug" => slug}) do
    status_page = Monitoring.get_status_page_with_status!(slug)

    if status_page.is_public do
      monitor_ids = Enum.map(status_page.monitors, & &1.id)

      region_data =
        Enum.map(monitor_ids, fn monitor_id ->
          case Monitoring.get_latest_check_with_regions(monitor_id) do
            nil -> %{monitor_id: monitor_id, regions: %{}}
            check -> %{monitor_id: monitor_id, regions: check.region_results || %{}}
          end
        end)

      json(conn, %{data: region_data})
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def show_public(conn, %{"slug" => slug}) do
    status_page = Monitoring.get_status_page_with_status!(slug)

    if status_page.is_public do
      overall_status = Monitoring.get_status_page_status(status_page.id)
      uptime = Monitoring.get_status_page_uptime(status_page.id, 30)

      monitor_ids = Enum.map(status_page.monitors, & &1.id)

      recent_incidents =
        Monitoring.list_recent_incidents_for_monitors(monitor_ids, 10)

      maintenance_windows =
        Maintenance.upcoming_maintenance(status_page.organization_id, days: 1)

      conn =
        if status_page.noindex do
          put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
        else
          conn
        end

      render(conn, :show_public,
        status_page: status_page,
        overall_status: overall_status,
        uptime: uptime,
        recent_incidents: recent_incidents,
        maintenance_windows: maintenance_windows
      )
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def index(conn, _params) do
    org = conn.assigns.current_organization
    status_pages = Monitoring.list_status_pages(org.id)
    render(conn, :index, status_pages: status_pages)
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    with :ok <- check_limit(org, :status_pages) do
      attrs =
        params
        |> Map.put("organization_id", org.id)
        |> Map.put("user_id", user.id)

      case Monitoring.create_status_page(attrs) do
        {:ok, page} ->
          Teams.log_action_from_conn(conn, "status_page.created", "status_page", page.id,
            metadata: %{name: page.name, slug: page.slug}
          )

          conn
          |> put_status(:created)
          |> render(:show, status_page: page)

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp check_limit(org, resource) do
    case Billing.check_plan_limit(org, resource) do
      :ok -> :ok
      {:error, message} -> {:error, :plan_limit, message}
    end
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    page = Monitoring.get_status_page!(id)

    if page.organization_id == org.id do
      render(conn, :show, status_page: page)
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def update(conn, %{"id" => id} = params) do
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    page = Monitoring.get_status_page!(id)

    if page.organization_id == org.id do
      case Monitoring.update_status_page(page, params) do
        {:ok, updated} ->
          if monitor_ids = params["monitor_ids"] do
            Monitoring.sync_status_page_monitors(updated, monitor_ids)
          end

          Teams.log_action_from_conn(conn, "status_page.updated", "status_page", updated.id,
            metadata: %{name: updated.name}
          )

          updated = Monitoring.get_status_page!(updated.id)
          render(conn, :show, status_page: updated)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    page = Monitoring.get_status_page!(id)

    if page.organization_id == org.id do
      case Monitoring.delete_status_page(page) do
        {:ok, _} ->
          Teams.log_action_from_conn(conn, "status_page.deleted", "status_page", page.id,
            metadata: %{name: page.name}
          )

          send_resp(conn, :no_content, "")
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
