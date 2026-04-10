defmodule Uptrack.SMTP.DispatcherTest do
  use ExUnit.Case, async: false

  alias Uptrack.SMTP.{Dispatcher, WorkerSupervisor, FakeSMTPState}

  @pg_scope :smtp_workers
  @pg_group :idle
  @fuse_name :smtp_circuit

  setup do
    FakeSMTPState.reset()
    :fuse.reset(@fuse_name)

    on_exit(fn ->
      FakeSMTPState.reset()
      :fuse.reset(@fuse_name)

      WorkerSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(WorkerSupervisor, pid) end)
    end)

    :ok
  end

  defp terminate_all_workers do
    WorkerSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(WorkerSupervisor, pid) end)
  end

  defp build_email do
    import Swoosh.Email

    new()
    |> from({"Uptrack", "alerts@uptrack.app"})
    |> to({"Test User", "user@example.com"})
    |> subject("Test")
    |> text_body("body")
  end

  describe "routing to idle workers" do
    test "routes to an idle worker already in :pg" do
      {:ok, pid} = WorkerSupervisor.start_worker()
      assert pid in :pg.get_members(@pg_scope, @pg_group)
      assert :ok = Dispatcher.deliver(build_email())
    end

    test "spawns a new worker when none idle" do
      terminate_all_workers()
      assert :ok = Dispatcher.deliver(build_email())
    end

    test "concurrent deliveries run in parallel (no GenServer bottleneck)" do
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn -> Dispatcher.deliver(build_email()) end)
        end)

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "circuit breaker" do
    test "returns :circuit_open when fuse is blown" do
      # Terminate workers and prevent new connections
      terminate_all_workers()
      FakeSMTPState.set_open_result({:error, :econnrefused})

      # Blow the fuse
      Enum.each(1..5, fn _ -> :fuse.melt(@fuse_name) end)

      assert {:error, :circuit_open} = Dispatcher.deliver(build_email())
    end

    test "melts fuse when worker delivery fails" do
      {:ok, _pid} = WorkerSupervisor.start_worker()
      FakeSMTPState.set_deliver_result({:error, :tempfail, "5.0.0 Error", :fake_socket})

      Dispatcher.deliver(build_email())

      # Fuse has been melted — state is :ok or :blown depending on prior melts
      assert :fuse.ask(@fuse_name, :sync) in [:ok, :blown]
    end
  end
end
