defmodule Uptrack.Monitoring.ObanCheckWorker do
  use Oban.Worker, queue: :monitor_checks, max_attempts: 3

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.CheckWorker
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"monitor_id" => monitor_id}}) do
    case Monitoring.get_monitor!(monitor_id) do
      nil ->
        Logger.warning("Monitor not found: #{monitor_id}")
        {:error, :monitor_not_found}

      monitor ->
        Logger.info("Performing Oban check for monitor: #{monitor.name}")
        CheckWorker.perform_check(monitor)
    end
  rescue
    e ->
      Logger.error("Check worker failed for monitor #{monitor_id}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end
end