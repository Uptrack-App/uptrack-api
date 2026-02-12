defmodule Uptrack.Monitoring.Scheduler do
  @moduledoc """
  Scheduler for managing monitoring checks across all active monitors.
  """

  use GenServer

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.CheckWorker
  require Logger

  # Check every 30 seconds for monitors that need checking
  @check_interval 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting monitoring scheduler")

    # Schedule the first check
    schedule_next_check()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_monitors, state) do
    Logger.debug("Checking for monitors that need monitoring")

    # Get all active monitors
    active_monitors = get_active_monitors()

    # Check which monitors need to be checked
    monitors_to_check = Enum.filter(active_monitors, &should_check_monitor?/1)

    Logger.info("Found #{length(monitors_to_check)} monitors that need checking")

    # Start async tasks for each monitor check
    Enum.each(monitors_to_check, fn monitor ->
      Task.Supervisor.start_child(
        Uptrack.TaskSupervisor,
        fn ->
          try do
            CheckWorker.perform_check(monitor)
          rescue
            e ->
              Logger.error("Error checking monitor #{monitor.name}: #{Exception.message(e)}")
              {:error, Exception.message(e)}
          end
        end
      )
    end)

    # Schedule the next check
    schedule_next_check()

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @doc """
  Manually triggers a check for a specific monitor.
  """
  def check_monitor(monitor_id) when is_integer(monitor_id) do
    case Monitoring.get_monitor!(monitor_id) do
      nil ->
        {:error, :not_found}

      monitor ->
        if monitor.status == "active" do
          Task.Supervisor.start_child(
            Uptrack.TaskSupervisor,
            fn -> CheckWorker.perform_check(monitor) end
          )

          {:ok, :scheduled}
        else
          {:error, :inactive}
        end
    end
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  # Gets all active monitors from all users.
  defp get_active_monitors do
    # This is a simplified version - in a real app you'd want to batch this
    # or use a more efficient query
    Monitoring.get_all_active_monitors()
  end

  # Determines if a monitor should be checked based on its interval and last check time.
  defp should_check_monitor?(monitor) do
    case Monitoring.get_latest_check(monitor.id) do
      nil ->
        # Never been checked, should check now
        true

      latest_check ->
        # Check if enough time has passed since last check
        time_since_last_check = DateTime.diff(DateTime.utc_now(), latest_check.checked_at)
        time_since_last_check >= monitor.interval
    end
  end

  # Schedules the next monitoring check.
  defp schedule_next_check do
    Process.send_after(self(), :check_monitors, @check_interval)
  end
end
