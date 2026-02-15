defmodule Uptrack.Monitoring.ConfirmationCheckWorker do
  @moduledoc """
  Oban worker that performs a confirmation re-check after an initial failure.

  When a monitor fails a check, instead of immediately creating an incident,
  this worker is scheduled to re-check after a short delay (typically 10 seconds).
  If the re-check also fails and the consecutive failure threshold is met,
  an incident is created. This eliminates false alerts from transient failures.
  """

  use Oban.Worker,
    queue: :monitor_checks,
    max_attempts: 1,
    unique: [period: 30, keys: [:monitor_id]]

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.CheckWorker
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"monitor_id" => monitor_id}}) do
    case Monitoring.get_monitor!(monitor_id) do
      nil ->
        Logger.warning("Monitor not found for confirmation check: #{monitor_id}")
        {:error, :monitor_not_found}

      monitor ->
        Logger.info("Performing confirmation check for monitor: #{monitor.name}")
        CheckWorker.perform_check(monitor)
    end
  rescue
    e ->
      Logger.error("Confirmation check failed for monitor #{monitor_id}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end
end
