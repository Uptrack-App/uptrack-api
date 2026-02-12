defmodule UptrackWeb.HealthController do
  @moduledoc """
  Health check endpoints for load balancers, Kubernetes, and monitoring.

  Provides two types of probes:
  - **Liveness** (`/healthz`): Is the application running?
  - **Readiness** (`/ready`): Is the application ready to serve traffic?

  Returns:
  - 200 OK if checks pass
  - 503 Service Unavailable if critical systems down
  """

  use UptrackWeb, :controller
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias OpenApiSpex.Schema
  alias UptrackWeb.HealthController.{HealthResponse, ReadinessResponse}

  tags ["Health"]

  operation :show,
    summary: "Liveness probe",
    description: """
    Lightweight health check for liveness probes. Returns 200 if the application
    process is running. Does not check external dependencies.

    Use this for Kubernetes liveness probes or basic uptime monitoring.
    """,
    responses: [
      ok: {"Healthy", "application/json", HealthResponse},
      service_unavailable: {"Unhealthy", "application/json", HealthResponse}
    ]

  operation :ready,
    summary: "Readiness probe",
    description: """
    Full health check for readiness probes. Verifies all dependencies:
    - Database connectivity (AppRepo)
    - Background job system (Oban/ObanRepo)
    - Idle prevention service

    Use this for Kubernetes readiness probes or load balancer health checks.
    """,
    responses: [
      ok: {"Ready", "application/json", ReadinessResponse},
      service_unavailable: {"Not Ready", "application/json", ReadinessResponse}
    ]

  @doc """
  GET /healthz - Liveness probe

  Minimal check to verify the application is running.
  Does NOT check external dependencies (database, etc).
  """
  def show(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{
      status: "alive",
      version: app_version(),
      node_region: System.get_env("NODE_REGION", "unknown"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  GET /ready - Readiness probe

  Checks:
  - Database connectivity (AppRepo)
  - Oban connectivity (ObanRepo)
  - Idle prevention service

  Returns JSON with status and diagnostics.
  """
  def ready(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      idle_prevention: check_idle_prevention()
    }

    all_healthy? = Enum.all?(checks, fn
      {:idle_prevention, %{}} -> true
      {_key, :ok} -> true
      {_key, _} -> false
    end)

    status_code = if all_healthy?, do: 200, else: 503
    status_text = if all_healthy?, do: "ready", else: "not_ready"

    conn
    |> put_status(status_code)
    |> json(%{
      status: status_text,
      version: app_version(),
      checks: checks,
      node_region: System.get_env("NODE_REGION", "unknown"),
      node_name: System.get_env("OBAN_NODE_NAME", "unknown"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp check_database do
    case Uptrack.AppRepo.query("SELECT 1", [], timeout: 5_000) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp check_oban do
    case Uptrack.ObanRepo.query("SELECT 1", [], timeout: 5_000) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp check_idle_prevention do
    case Uptrack.Health.IdlePrevention.get_stats() do
      %{} = stats -> stats
      {:error, _} -> %{}
    end
  catch
    :exit, _ -> %{}
  end

  defp app_version do
    case :application.get_key(:uptrack, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "unknown"
    end
  end
end

# OpenAPI Schemas for Health Endpoints

defmodule UptrackWeb.HealthController.HealthResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "HealthResponse",
    description: "Liveness probe response",
    type: :object,
    required: [:status, :timestamp],
    properties: %{
      status: %Schema{type: :string, description: "Health status", example: "alive"},
      version: %Schema{type: :string, description: "Application version", example: "0.1.0"},
      node_region: %Schema{type: :string, description: "Node region", example: "eu-central"},
      timestamp: %Schema{type: :string, format: :"date-time", description: "Check timestamp"}
    }
  })
end

defmodule UptrackWeb.HealthController.ReadinessResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReadinessResponse",
    description: "Readiness probe response with dependency checks",
    type: :object,
    required: [:status, :checks, :timestamp],
    properties: %{
      status: %Schema{type: :string, description: "Readiness status", enum: ["ready", "not_ready"]},
      version: %Schema{type: :string, description: "Application version", example: "0.1.0"},
      checks: %Schema{
        type: :object,
        description: "Individual dependency check results",
        properties: %{
          database: %Schema{type: :string, description: "Database status"},
          oban: %Schema{type: :string, description: "Oban job queue status"},
          idle_prevention: %Schema{type: :object, description: "Idle prevention stats"}
        }
      },
      node_region: %Schema{type: :string, description: "Node region"},
      node_name: %Schema{type: :string, description: "Oban node name"},
      timestamp: %Schema{type: :string, format: :"date-time", description: "Check timestamp"}
    }
  })
end
