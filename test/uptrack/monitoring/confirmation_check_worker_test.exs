defmodule Uptrack.Monitoring.ConfirmationCheckWorkerTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring.ConfirmationCheckWorker

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  describe "perform/1" do
    test "handles missing monitor gracefully" do
      job = %Oban.Job{
        args: %{"monitor_id" => Ecto.UUID.generate()}
      }

      result = ConfirmationCheckWorker.perform(job)
      assert {:error, _} = result
    end
  end
end
