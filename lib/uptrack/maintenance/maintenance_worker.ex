defmodule Uptrack.Maintenance.MaintenanceWorker do
  @moduledoc """
  Oban worker that runs periodically to activate and complete maintenance windows.
  Runs every minute via the Oban Cron plugin.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  alias Uptrack.Maintenance
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    {activated, _} = Maintenance.activate_scheduled_windows()
    {completed, _} = Maintenance.complete_expired_windows()

    if activated > 0, do: Logger.info("Activated #{activated} maintenance windows")
    if completed > 0, do: Logger.info("Completed #{completed} maintenance windows")

    :ok
  end
end
