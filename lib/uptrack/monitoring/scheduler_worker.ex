defmodule Uptrack.Monitoring.SchedulerWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Uptrack.Monitoring

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    active_monitors = Monitoring.get_all_active_monitors()

    for monitor <- active_monitors do
      if should_check_monitor?(monitor) do
        %{monitor_id: monitor.id}
        |> Uptrack.Monitoring.ObanCheckWorker.new()
        |> Oban.insert(repo: Uptrack.ObanRepo)
      end
    end

    :ok
  end

  defp should_check_monitor?(monitor) do
    case Uptrack.Cache.get_latest_check(monitor.id) do
      nil ->
        true

      latest_check ->
        seconds_since_check = DateTime.diff(DateTime.utc_now(), latest_check.checked_at, :second)
        seconds_since_check >= monitor.interval
    end
  end
end