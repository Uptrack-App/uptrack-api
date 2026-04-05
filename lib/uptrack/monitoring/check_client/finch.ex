defmodule Uptrack.Monitoring.CheckClient.Finch do
  @moduledoc """
  Finch pool-based HTTP check client. Wraps existing CheckExecutor.

  Used as fallback when Gun is disabled via feature flag.
  """

  @behaviour Uptrack.Monitoring.CheckClient

  alias Uptrack.Monitoring.{Monitor, CheckExecutor}

  @impl true
  def open_connection(_monitor), do: {:ok, :finch_pool}

  @impl true
  def close_connection(_conn), do: :ok

  @impl true
  def check(%Monitor{} = monitor, _conn) do
    CheckExecutor.execute(monitor)
  end
end
