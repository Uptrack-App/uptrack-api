defmodule UptrackWeb.Api.StatusPageController do
  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  action_fallback UptrackWeb.Api.FallbackController

  def show_public(conn, %{"slug" => slug}) do
    status_page = Monitoring.get_status_page_with_status!(slug)

    if status_page.is_public do
      overall_status = Monitoring.get_status_page_status(status_page.id)
      uptime = Monitoring.get_status_page_uptime(status_page.id, 30)

      recent_incidents =
        Monitoring.list_recent_incidents(status_page.organization_id, 10)

      render(conn, :show_public,
        status_page: status_page,
        overall_status: overall_status,
        uptime: uptime,
        recent_incidents: recent_incidents
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

    attrs =
      params
      |> Map.put("organization_id", org.id)
      |> Map.put("user_id", user.id)

    case Monitoring.create_status_page(attrs) do
      {:ok, page} ->
        conn
        |> put_status(:created)
        |> render(:show, status_page: page)

      {:error, changeset} ->
        {:error, changeset}
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
    org = conn.assigns.current_organization

    page = Monitoring.get_status_page!(id)

    if page.organization_id == org.id do
      case Monitoring.update_status_page(page, params) do
        {:ok, updated} ->
          if monitor_ids = params["monitor_ids"] do
            Monitoring.sync_status_page_monitors(updated, monitor_ids)
          end

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
    org = conn.assigns.current_organization

    page = Monitoring.get_status_page!(id)

    if page.organization_id == org.id do
      case Monitoring.delete_status_page(page) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
