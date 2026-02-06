defmodule Uptrack.Monitoring.HeartbeatCheckerWorker do
  @moduledoc """
  Oban worker that checks for missed heartbeats.

  Runs every minute to find heartbeat monitors that haven't
  checked in within their expected interval + grace period.

  Creates incidents for monitors with missed heartbeats.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Uptrack.Monitoring.Heartbeat

  @impl Oban.Worker
  def perform(_job) do
    Heartbeat.check_missed_heartbeats()
    :ok
  end
end
