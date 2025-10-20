defmodule UptrackWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.

  Returns:
  - 200 OK if all systems healthy
  - 503 Service Unavailable if critical systems down
  """

  use UptrackWeb, :controller
  require Logger

  @doc """
  GET /healthz

  Checks:
  - Database connectivity (AppRepo)
  - Oban connectivity (ObanRepo)

  Returns JSON with status and optional diagnostics.
  """
  def show(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      idle_prevention: check_idle_prevention(),
      node_region: System.get_env("NODE_REGION", "unknown"),
      node_name: System.get_env("OBAN_NODE_NAME", "unknown")
    }

    all_healthy? = Enum.all?(checks, fn
      {:node_region, _} -> true
      {:node_name, _} -> true
      {:idle_prevention, %{} } -> true
      {_key, :ok} -> true
      {_key, _} -> false
    end)

    status_code = if all_healthy?, do: 200, else: 503
    status_text = if all_healthy?, do: "healthy", else: "unhealthy"

    conn
    |> put_status(status_code)
    |> json(%{
      status: status_text,
      checks: checks,
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
      {:error, _} -> %{error: "IdlePrevention not running"}
    end
  rescue
    _exception -> %{error: "IdlePrevention not available"}
  end
end
