defmodule Uptrack.Monitoring.CheckFailureCleanupWorker do
  @moduledoc """
  Oban cron worker that deletes monitor_check_failures older than 30 days.
  Scheduled daily.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  @retention_days 30

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_days * 86400, :second)
    count = Uptrack.Monitoring.CheckFailures.delete_older_than(cutoff)
    if count > 0 do
      Logger.info("CheckFailureCleanupWorker: deleted #{count} failure rows older than #{@retention_days} days")
    end
    :ok
  end
end
