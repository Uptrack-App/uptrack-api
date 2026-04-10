defmodule Uptrack.SMTP.FleetTest do
  use ExUnit.Case, async: false

  alias Uptrack.SMTP.{Fleet, WorkerSupervisor, FakeSMTPState}

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
    |> subject("Incident alert")
    |> text_body("Monitor is down")
    |> html_body("<p>Monitor is down</p>")
  end

  describe "startup" do
    test "fuse is installed — :fuse.ask does not return error" do
      result = :fuse.ask(@fuse_name, :sync)
      assert result in [:ok, :blown], "expected fuse to be installed, got #{inspect(result)}"
    end

    test "Fleet GenServer is running" do
      assert Process.whereis(Fleet) != nil
    end
  end

  describe "deliver/1" do
    test "returns {:ok, %{}} on successful delivery" do
      assert {:ok, %{}} = Fleet.deliver(build_email())
    end

    test "returns {:error, :circuit_open} when circuit is open" do
      terminate_all_workers()
      FakeSMTPState.set_open_result({:error, :econnrefused})
      Enum.each(1..5, fn _ -> :fuse.melt(@fuse_name) end)

      assert {:error, :circuit_open} = Fleet.deliver(build_email())
    end

    test "returns {:error, reason} on delivery failure" do
      FakeSMTPState.set_deliver_result({:error, :tempfail, "5.0.0 Error", :fake_socket})

      # Start a fresh worker with the error configured
      {:ok, _pid} = WorkerSupervisor.start_worker()

      result = Fleet.deliver(build_email())
      assert match?({:error, _}, result)
    end
  end

  describe "FleetAdapter" do
    test "deliver/2 delegates to Fleet.deliver/1" do
      assert {:ok, %{}} = Uptrack.SMTP.FleetAdapter.deliver(build_email(), [])
    end
  end
end
