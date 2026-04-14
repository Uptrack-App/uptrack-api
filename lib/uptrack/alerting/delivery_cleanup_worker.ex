defmodule Uptrack.Alerting.DeliveryCleanupWorker do
  @moduledoc """
  Oban cron worker that deletes notification_deliveries older than 7 days.
  Scheduled daily at 03:00 UTC.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Uptrack.AppRepo

  @retention_days 7

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_days * 86400, :second)

    {count, _} =
      AppRepo.query!(
        "DELETE FROM app.notification_deliveries WHERE inserted_at < $1",
        [cutoff]
      )
      |> then(fn %{num_rows: n} -> {n, nil} end)

    if count > 0 do
      require Logger
      Logger.info("DeliveryCleanupWorker: deleted #{count} notification deliveries older than #{@retention_days} days")
    end

    :ok
  end
end
