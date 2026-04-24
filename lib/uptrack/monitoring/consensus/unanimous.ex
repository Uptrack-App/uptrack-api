defmodule Uptrack.Monitoring.Consensus.Unanimous do
  @moduledoc """
  Legacy consensus strategy: declare DOWN only when every expected
  worker agrees. Preserved as a single-flag rollback path in case the
  new `RollingCount` strategy misbehaves in production.

  Not recommended beyond that: a flaky worker that times out silences
  real regional outages. See `RollingCount` for the production default.
  """

  @behaviour Uptrack.Monitoring.Consensus.Strategy

  alias Uptrack.Monitoring.CheckHistory

  @impl true
  def decide(_monitor_id, history, opts) do
    trusted_workers = Keyword.get_lazy(opts, :trusted_workers, fn -> CheckHistory.workers(history) end)
    expected = length(trusted_workers)
    received = received_count(history, trusted_workers)

    down_count =
      Enum.count(trusted_workers, fn w ->
        case CheckHistory.last_n(history, w, 1) do
          [:down | _] -> true
          _ -> false
        end
      end)

    cond do
      expected == 0 ->
        {:insufficient_data, %{reason: :no_workers}}

      received < expected ->
        {:up, %{received: received, expected: expected, down: down_count, reason: :missing_sample}}

      down_count == expected ->
        {:down, %{unanimous: true, down: down_count, expected: expected}}

      true ->
        {:up, %{unanimous: false, down: down_count, expected: expected}}
    end
  end

  defp received_count(history, workers) do
    Enum.count(workers, fn w ->
      case CheckHistory.last_n(history, w, 1) do
        [] -> false
        _ -> true
      end
    end)
  end
end
