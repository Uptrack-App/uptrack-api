defmodule UptrackWeb.Api.MaintenanceWindowController do
  use UptrackWeb, :controller

  alias Uptrack.Maintenance

  action_fallback UptrackWeb.Api.FallbackController

  def index(conn, params) do
    org = conn.assigns.current_organization

    opts =
      []
      |> then(fn o -> if params["status"], do: Keyword.put(o, :status, params["status"]), else: o end)
      |> then(fn o -> if params["monitor_id"], do: Keyword.put(o, :monitor_id, params["monitor_id"]), else: o end)

    windows = Maintenance.list_maintenance_windows(org.id, opts)
    render(conn, :index, maintenance_windows: windows)
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    case Maintenance.get_organization_maintenance_window(org.id, id) do
      nil -> {:error, :not_found}
      window -> render(conn, :show, maintenance_window: window)
    end
  end

  def create(conn, params) do
    org = conn.assigns.current_organization

    attrs =
      params
      |> Map.take(["title", "description", "start_time", "end_time", "recurrence", "monitor_id"])
      |> Map.put("organization_id", org.id)
      |> parse_datetimes()

    case Maintenance.create_maintenance_window(attrs) do
      {:ok, window} ->
        conn
        |> put_status(:created)
        |> render(:show, maintenance_window: window)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    org = conn.assigns.current_organization

    attrs =
      params
      |> Map.take(["title", "description", "start_time", "end_time", "recurrence", "status"])
      |> parse_datetimes()

    with window when not is_nil(window) <- Maintenance.get_organization_maintenance_window(org.id, id),
         {:ok, updated} <- Maintenance.update_maintenance_window(window, attrs) do
      render(conn, :show, maintenance_window: updated)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    with window when not is_nil(window) <- Maintenance.get_organization_maintenance_window(org.id, id),
         {:ok, _} <- Maintenance.delete_maintenance_window(window) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetimes(attrs) do
    attrs
    |> maybe_parse_datetime("start_time")
    |> maybe_parse_datetime("end_time")
  end

  defp maybe_parse_datetime(attrs, key) do
    case Map.get(attrs, key) do
      nil -> attrs
      str when is_binary(str) ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> Map.put(attrs, key, DateTime.truncate(dt, :second))
          _ -> attrs
        end
      _ -> attrs
    end
  end
end
