defmodule UptrackWeb.Api.MonitorController do
  use UptrackWeb, :controller

  require Logger

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
  def index(conn, params) do
    org = conn.assigns.current_organization
    result = Monitoring.list_monitors(org.id, params)

    render(conn, :index, result: result)
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
      |> Map.merge(params |> Map.take(["name", "interval", "timeout", "monitor_type", "confirmation_threshold", "reminder_interval_minutes"]) |> atomize_keys())
      |> Map.update(:settings, %{}, fn default_settings ->
        default_settings |> Map.merge(type_settings) |> Map.merge(user_settings)
      end)

    interval = attrs[:interval] || defaults[:interval] || 300

    with :ok <- check_private_url(url),
         :ok <- check_request_body(org.plan, user_settings),
         :ok <- check_limit(org, :monitors),
         :ok <- check_interval(org, interval) do
      case Monitoring.create_monitor(attrs) do
        {:ok, monitor} ->
          # Sync region assignments if provided
          if region_ids = params["region_ids"] do
            Monitoring.sync_monitor_regions(monitor.id, region_ids)
          end

          Teams.log_action_from_conn(conn, "monitor.created", "monitor", monitor.id,
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
        {:ok, uptime} = Uptrack.Metrics.Reader.get_uptime_percentage(monitor.id)
        {:ok, region_results} = Uptrack.Metrics.Reader.get_region_response_times(monitor.id)
        monitor = %{monitor | uptime_percentage: uptime, region_results: region_results}
        render(conn, :show, monitor: monitor)
    end
  end

  @doc """
  Updates a monitor.
  PATCH /api/monitors/:id
  """
  def update(conn, %{"id" => id} = params) do
    _user = conn.assigns.current_user
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
          if region_ids = params["region_ids"] do
            Monitoring.sync_monitor_regions(updated.id, region_ids)
          end

          Teams.log_action_from_conn(conn, "monitor.updated", "monitor", updated.id,
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
  Bulk action on multiple monitors.
  POST /api/monitors/bulk

  Body: {"action": "pause"|"resume"|"delete"|"update_interval", "monitor_ids": [...], "interval": 60}
  """
  def bulk_action(conn, %{"action" => action, "monitor_ids" => ids} = params)
      when action in ["pause", "resume", "delete", "update_interval"] and is_list(ids) do
    org = conn.assigns.current_organization

    # Filter to only monitors belonging to this org
    owned_ids =
      Monitoring.list_organization_monitor_ids(org.id, ids)

    count =
      case action do
        "pause" ->
          Monitoring.bulk_update_monitors(owned_ids, status: "paused")

        "resume" ->
          Monitoring.bulk_update_monitors(owned_ids, status: "active")

        "delete" ->
          Monitoring.bulk_delete_monitors(owned_ids)

        "update_interval" ->
          interval = params["interval"]
          if is_integer(interval) and interval >= 30 do
            Monitoring.bulk_update_monitors(owned_ids, interval: interval)
          else
            0
          end
      end

    Teams.log_action_from_conn(conn, "monitor.bulk_#{action}", "monitor", nil,
      metadata: %{count: count, ids: owned_ids}
    )

    json(conn, %{data: %{count: count, action: action}})
  end

  def bulk_action(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid action or missing monitor_ids"})
  end

  @doc """
  Deletes a monitor.
  DELETE /api/monitors/:id
  """
  def delete(conn, %{"id" => id}) do
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    with monitor when not is_nil(monitor) <- Monitoring.get_organization_monitor(org.id, id),
         {:ok, _} <- Monitoring.delete_monitor(monitor) do
      Teams.log_action_from_conn(conn, "monitor.deleted", "monitor", monitor.id,
        metadata: %{name: monitor.name}
      )

      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists available check regions.
  GET /api/regions
  """
  def regions(conn, _params) do
    import Ecto.Query
    regions =
      Uptrack.Monitoring.Region
      |> where([r], r.is_active == true)
      |> order_by([r], asc: r.code)
      |> Uptrack.AppRepo.all()
      |> Enum.map(fn r -> %{id: r.id, code: r.code, name: r.name} end)

    json(conn, %{data: regions})
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
        case Uptrack.Metrics.Reader.get_recent_checks(monitor_id, limit) do
          {:ok, checks} ->
            # Pull DOWN detail rows for this monitor so we can enrich
            # failed rows with body/headers/error text.
            failures = Uptrack.Monitoring.CheckFailures.recent_for_monitor(monitor_id, limit)
            render(conn, :checks_from_vm, checks: checks, failures: failures)

          {:error, reason} ->
            Logger.warning("VM checks query failed for monitor #{monitor_id}: #{inspect(reason)}")
            {:error, :service_unavailable}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp check_private_url(url) do
    if Uptrack.AbusePrevention.private_url?(url) do
      {:error, :plan_limit, "Monitoring private/localhost URLs is not allowed."}
    else
      :ok
    end
  end

  defp check_request_body(plan, settings) do
    has_body = Map.has_key?(settings, "body") and settings["body"] not in [nil, ""]

    if has_body and not Uptrack.AbusePrevention.request_body_allowed?(plan) do
      {:error, :plan_limit, "Custom request body is available on paid plans. Upgrade to Pro for POST monitoring."}
    else
      :ok
    end
  end

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
