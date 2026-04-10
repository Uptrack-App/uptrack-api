defmodule Uptrack.SMTP.WorkerSupervisor do
  @moduledoc """
  DynamicSupervisor managing the lifecycle of SMTP worker processes.
  Each worker holds one persistent gen_smtp connection.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker do
    DynamicSupervisor.start_child(__MODULE__, {Uptrack.SMTP.Worker, []})
  end
end
