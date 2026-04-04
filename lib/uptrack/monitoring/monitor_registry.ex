defmodule Uptrack.Monitoring.MonitorRegistry do
  @moduledoc """
  Registry for looking up MonitorProcess by monitor_id.

  Uses Elixir's built-in Registry — O(1) lookups via ETS.
  """

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @doc "Returns a via tuple for registering/looking up a process."
  def via(monitor_id) do
    {:via, Registry, {__MODULE__, monitor_id}}
  end

  @doc "Looks up a MonitorProcess pid by monitor_id."
  def lookup(monitor_id) do
    case Registry.lookup(__MODULE__, monitor_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc "Returns all registered monitor_ids."
  def all_ids do
    Registry.select(__MODULE__, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc "Returns count of running monitor processes."
  def count do
    Registry.count(__MODULE__)
  end
end
