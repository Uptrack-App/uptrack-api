defmodule Uptrack.SMTP.Fleet do
  @moduledoc """
  Public API for the SMTP connection fleet.

  Installs the fuse circuit breaker on start and warms the minimum worker
  pool. Exposes deliver/1 as a drop-in for Mailer.deliver/1.
  """

  use GenServer
  require Logger

  @fuse_name :smtp_circuit
  @min_workers 2

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def deliver(%Swoosh.Email{} = email) do
    case Uptrack.SMTP.Dispatcher.deliver(email) do
      :ok ->
        {:ok, %{}}

      {:error, :circuit_open} = err ->
        Logger.warning("[SMTPFleet] Circuit open — Oban will retry")
        err

      {:error, reason} = err ->
        Logger.error("[SMTPFleet] Delivery failed: #{inspect(reason)}")
        err
    end
  end

  # --- Callbacks ---

  @impl GenServer
  def init(_opts) do
    # Install fuse before any worker tries to use it.
    # opens after >4 failures in 10s (i.e. 5th failure trips it), resets after 5s
    :fuse.install(@fuse_name, {{:standard, 4, 10_000}, {:reset, 5_000}})
    # Warm minimum workers after supervision tree settles
    Process.send_after(self(), :warm_workers, 500)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:warm_workers, state) do
    Enum.each(1..@min_workers, fn _ ->
      case Uptrack.SMTP.WorkerSupervisor.start_worker() do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("[SMTPFleet] Could not warm worker: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end
end
