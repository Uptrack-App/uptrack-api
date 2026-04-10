defmodule Uptrack.SMTP.WorkerTest do
  use ExUnit.Case, async: false

  alias Uptrack.SMTP.{Worker, WorkerSupervisor, FakeSMTPState}

  @pg_scope :smtp_workers
  @pg_group :idle

  setup do
    FakeSMTPState.reset()

    on_exit(fn ->
      FakeSMTPState.reset()

      WorkerSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(WorkerSupervisor, pid) end)
    end)

    :ok
  end

  defp start_worker do
    {:ok, pid} = WorkerSupervisor.start_worker()
    pid
  end

  defp build_email do
    import Swoosh.Email

    new()
    |> from({"Uptrack", "alerts@uptrack.app"})
    |> to({"Test User", "user@example.com"})
    |> subject("Test alert")
    |> text_body("Monitor is down")
    |> html_body("<p>Monitor is down</p>")
  end

  describe "start / :pg registration" do
    test "worker joins :pg group when started" do
      pid = start_worker()
      assert pid in :pg.get_members(@pg_scope, @pg_group)
    end

    test "worker rejoins :pg group after delivering" do
      pid = start_worker()
      assert :ok = Worker.deliver(pid, build_email())
      assert pid in :pg.get_members(@pg_scope, @pg_group)
    end
  end

  describe "deliver/2" do
    test "returns :ok on successful delivery" do
      pid = start_worker()
      assert :ok = Worker.deliver(pid, build_email())
    end

    test "terminates worker on SMTP error, does not rejoin :pg" do
      pid = start_worker()
      ref = Process.monitor(pid)

      FakeSMTPState.set_deliver_result({:error, :tempfail, "Try again", :fake_socket})

      result = Worker.deliver(pid, build_email())
      assert {:error, _} = result

      # Wait for worker to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000

      refute pid in :pg.get_members(@pg_scope, @pg_group)
    end
  end

  describe "child_spec" do
    test "restart is :transient so idle timeout does not cause a restart" do
      assert Worker.child_spec([]).restart == :transient
    end
  end

  describe "connection fallback" do
    test "fails to start when both primary and fallback SMTP are down" do
      FakeSMTPState.set_open_result({:error, :econnrefused})
      assert {:error, _} = WorkerSupervisor.start_worker()
    end
  end
end
