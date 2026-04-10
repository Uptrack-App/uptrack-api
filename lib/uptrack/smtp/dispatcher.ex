defmodule Uptrack.SMTP.Dispatcher do
  @moduledoc """
  Routes email delivery to idle SMTP workers across the cluster.

  This is a plain module — no GenServer, no serialization point. Each caller
  independently discovers an idle worker via :pg and delivers directly. Multiple
  concurrent deliveries run fully in parallel.

  Strategy:
  1. Pick a random idle worker from :pg group (cluster-wide, any node)
  2. Route directly to that worker via Erlang message passing
  3. If none idle, check fuse circuit breaker
  4. If circuit closed, spawn a new worker and deliver through it
  5. If circuit open (Stalwart overwhelmed), return {:error, :circuit_open}
  """

  require Logger

  @pg_scope :smtp_workers
  @pg_group :idle
  @fuse_name :smtp_circuit

  def deliver(email) do
    case pick_idle_worker() do
      {:ok, pid} ->
        deliver_via(pid, email)

      :none ->
        case :fuse.ask(@fuse_name, :sync) do
          :ok ->
            spawn_and_deliver(email)

          :blown ->
            Logger.warning("[SMTPDispatcher] Circuit open — Stalwart overwhelmed")
            {:error, :circuit_open}

          {:error, :not_found} ->
            Logger.error("[SMTPDispatcher] fuse :smtp_circuit not installed — check Fleet startup")
            {:error, :circuit_not_initialized}
        end
    end
  end

  # --- Private ---

  defp pick_idle_worker do
    # :pg automatically removes dead processes (local and cross-node).
    # Trust its membership list; no need for Process.alive? which returns
    # false for remote PIDs regardless of liveness.
    case :pg.get_members(@pg_scope, @pg_group) do
      [] -> :none
      members -> {:ok, Enum.random(members)}
    end
  end

  defp deliver_via(pid, email) do
    case Uptrack.SMTP.Worker.deliver(pid, email) do
      :ok ->
        :ok

      {:error, reason} ->
        :fuse.melt(@fuse_name)
        {:error, reason}
    end
  rescue
    _ ->
      :fuse.melt(@fuse_name)
      {:error, :worker_unavailable}
  end

  defp spawn_and_deliver(email) do
    case Uptrack.SMTP.WorkerSupervisor.start_worker() do
      {:ok, pid} ->
        deliver_via(pid, email)

      {:error, reason} ->
        :fuse.melt(@fuse_name)
        Logger.error("[SMTPDispatcher] Failed to spawn worker: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
