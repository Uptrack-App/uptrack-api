defmodule Uptrack.Monitoring.CheckClient.Mock do
  @moduledoc """
  Mock check client for tests. Returns configurable results without HTTP calls.

  Configure results via process dictionary or default to "up":

      Process.put(:mock_check_result, %{status: "down", error_message: "test"})
  """

  @behaviour Uptrack.Monitoring.CheckClient

  alias Uptrack.Monitoring.Monitor

  @impl true
  def open_connection(_monitor), do: {:ok, :mock_conn}

  @impl true
  def close_connection(_conn), do: :ok

  @impl true
  def check(%Monitor{} = monitor, _conn) do
    custom = Process.get(:mock_check_result)

    base = %{
      monitor_id: monitor.id,
      status: "up",
      status_code: 200,
      response_time: 42,
      checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      response_headers: %{},
      response_body: nil,
      error_message: nil
    }

    if custom, do: Map.merge(base, custom), else: base
  end
end
