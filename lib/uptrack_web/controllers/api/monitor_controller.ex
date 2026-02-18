defmodule UptrackWeb.Api.MonitorController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.SmartDefaults
  alias Uptrack.Teams

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

    # Build attrs from smart defaults + overrides
    defaults = SmartDefaults.from_url(url)

    # Deep merge user-provided settings into smart defaults
    user_settings = Map.get(params, "settings", %{})
    # Merge type-specific defaults for non-auto-detected types (ssl, dns)
    monitor_type = params["monitor_type"] || defaults[:monitor_type]
    type_settings = SmartDefaults.type_defaults(to_string(monitor_type))

    attrs =
      defaults
      |> Map.merge(%{organization_id: org.id, user_id: user.id})
      |> Map.merge(params |> Map.take(["name", "interval", "timeout", "monitor_type", "confirmation_threshold"]) |> atomize_keys())
      |> Map.update(:settings, %{}, fn default_settings ->
        default_settings |> Map.merge(type_settings) |> Map.merge(user_settings)
      end)

    interval = attrs[:interval] || defaults[:interval] || 300

    with :ok <- check_limit(org, :monitors),
         :ok <- check_interval(org, interval) do
      case Monitoring.create_monitor(attrs) do
        {:ok, monitor} ->
          Teams.log_action(org.id, user.id, "monitor.created", "monitor", monitor.id,
            metadata: %{name: monitor.name, monitor_type: monitor.monitor_type}
          )

          conn
          |> put_status(:created)
          |> render(:show, monitor: monitor)

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Shows a single monitor.
  GET /api/monitors/:id
  """
  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    case Monitoring.get_organization_monitor(org.id, id) do
      nil ->
        {:error, :not_found}

      monitor ->
        uptime = Monitoring.get_uptime_percentage(monitor.id)
        monitor = %{monitor | uptime_percentage: uptime}
        render(conn, :show, monitor: monitor)
    end
  end

  @doc """
  Updates a monitor.
  PATCH /api/monitors/:id
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    interval = params["interval"]

    with :ok <- if(interval, do: check_interval(org, interval), else: :ok),
         monitor when not is_nil(monitor) <- Monitoring.get_organization_monitor(org.id, id) do
      # Deep merge user-provided settings into existing monitor settings
      params =
        case Map.get(params, "settings") do
          user_settings when is_map(user_settings) and user_settings != %{} ->
            merged = Map.merge(monitor.settings || %{}, user_settings)
            Map.put(params, "settings", merged)

          _ ->
            params
        end

      case Monitoring.update_monitor(monitor, params) do
        {:ok, updated} ->
          Teams.log_action(org.id, user.id, "monitor.updated", "monitor", updated.id,
            metadata: %{name: updated.name}
          )

          render(conn, :show, monitor: updated)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
      {:error, :plan_limit, _} = err -> err
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a monitor.
  DELETE /api/monitors/:id
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    with monitor when not is_nil(monitor) <- Monitoring.get_organization_monitor(org.id, id),
         {:ok, _} <- Monitoring.delete_monitor(monitor) do
      Teams.log_action(org.id, user.id, "monitor.deleted", "monitor", monitor.id,
        metadata: %{name: monitor.name}
      )

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

  defp check_limit(org, resource) do
    case Billing.check_plan_limit(org, resource) do
      :ok -> :ok
      {:error, message} -> {:error, :plan_limit, message}
    end
  end

  defp check_interval(org, interval) when is_binary(interval) do
    case Integer.parse(interval) do
      {n, _} -> check_interval(org, n)
      :error -> :ok
    end
  end

  defp check_interval(org, interval) when is_integer(interval) do
    case Billing.check_interval_limit(org, interval) do
      :ok -> :ok
      {:error, message} -> {:error, :plan_limit, message}
    end
  end

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
