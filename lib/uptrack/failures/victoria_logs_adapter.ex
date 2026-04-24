defmodule Uptrack.Failures.VictoriaLogsAdapter do
  @moduledoc """
  Forensic-event writer that routes through the sharded Batcher.
  Non-blocking: a single `GenServer.cast` to the owning shard.
  """

  @behaviour Uptrack.Failures

  alias Uptrack.Failures.{Event, Router, VlClient}
  alias Uptrack.Failures.Batcher.Shard

  @impl true
  def record(%Event{} = event) do
    line = VlClient.encode(event)
    shard = Router.shard_name(event.monitor_id)
    Shard.write(shard, line)
    :ok
  end
end
