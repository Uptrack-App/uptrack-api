defmodule Uptrack.MonitoringFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Uptrack.Monitoring` context.
  """

  @doc """
  Generate a monitor.
  """
  def monitor_fixture(attrs \\ %{}) do
    {:ok, monitor} =
      attrs
      |> Enum.into(%{
        alert_contacts: %{},
        description: "some description",
        interval: 42,
        monitor_type: "some monitor_type",
        name: "some name",
        settings: %{},
        status: "some status",
        timeout: 42,
        url: "some url"
      })
      |> Uptrack.Monitoring.create_monitor()

    monitor
  end
end
