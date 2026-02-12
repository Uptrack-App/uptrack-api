defmodule UptrackWeb.Api.MonitorController do
  use UptrackWeb, :controller

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.SmartDefaults

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Returns smart defaults for a URL.
  POST /api/monitors/smart-defaults

  Body: {"url": "example.com"}

  Returns suggested monitor configuration based on URL analysis.
  """
  def smart_defaults(conn, %{"url" => url}) do
    defaults = SmartDefaults.from_url(url)

    # Also get suggested regions
    timezone = get_req_header(conn, "x-timezone") |> List.first()
    regions = SmartDefaults.suggest_regions(timezone)

    json(conn, %{
      data: Map.put(defaults, :suggested_regions, regions)
    })
  end

  @doc """
  Lists monitors for the current organization.
  GET /api/monitors
  """
  def index(conn, _params) do
    org = conn.assigns.current_organization
    monitors = Monitoring.list_monitors(org.id)

    render(conn, :index, monitors: monitors)
  end

  @doc """
  Creates a new monitor.
  POST /api/monitors

  Accepts minimal input (just URL) and applies smart defaults.
  """
  def create(conn, %{"url" => url} = params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    # Get smart defaults
    defaults = SmartDefaults.from_url(url)

    # Merge with any provided overrides
    attrs =
      defaults
      |> Map.merge(%{
        organization_id: org.id,
        user_id: user.id
      })
      |> Map.merge(params |> Map.take(["name", "interval", "timeout", "settings"]) |> atomize_keys())

    case Monitoring.create_monitor(attrs) do
      {:ok, monitor} ->
        conn
        |> put_status(:created)
        |> render(:show, monitor: monitor)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Shows a single monitor.
  GET /api/monitors/:id
  """
  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    case Monitoring.get_organization_monitor(org.id, id) do
      nil -> {:error, :not_found}
      monitor -> render(conn, :show, monitor: monitor)
    end
  end

  @doc """
  Updates a monitor.
  PATCH /api/monitors/:id
  """
  def update(conn, %{"id" => id} = params) do
    org = conn.assigns.current_organization

    with monitor when not is_nil(monitor) <- Monitoring.get_organization_monitor(org.id, id),
         {:ok, updated} <- Monitoring.update_monitor(monitor, params) do
      render(conn, :show, monitor: updated)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a monitor.
  DELETE /api/monitors/:id
  """
  def delete(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    with monitor when not is_nil(monitor) <- Monitoring.get_organization_monitor(org.id, id),
         {:ok, _} <- Monitoring.delete_monitor(monitor) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists recent checks for a monitor.
  GET /api/monitors/:monitor_id/checks
  """
  def checks(conn, %{"monitor_id" => monitor_id} = params) do
    org = conn.assigns.current_organization
    limit = params |> Map.get("limit", "20") |> String.to_integer() |> min(100)

    case Monitoring.get_organization_monitor(org.id, monitor_id) do
      nil ->
        {:error, :not_found}

      _monitor ->
        checks = Monitoring.get_recent_checks(monitor_id, limit)
        render(conn, :checks, checks: checks)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
