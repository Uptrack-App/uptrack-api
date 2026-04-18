defmodule Uptrack.Monitoring.CheckFailures do
  @moduledoc """
  Write/read helpers for the DOWN-check detail log.
  """

  import Ecto.Query
  alias Uptrack.AppRepo
  alias Uptrack.Monitoring.{CheckFailure, MonitorCheck}

  @max_body_bytes 4_000
  @max_error_bytes 500

  @doc """
  Persists a failure row for a DOWN check. No-op for UP checks or when the
  insert fails — this is best-effort telemetry, never blocks the check pipeline.
  """
  def record(%MonitorCheck{status: "down"} = check) do
    attrs = %{
      monitor_id: check.monitor_id,
      status_code: check.status_code,
      response_time: check.response_time,
      error_message: truncate(check.error_message, @max_error_bytes),
      response_body: truncate(check.response_body, @max_body_bytes),
      response_headers: sanitize_headers(check.response_headers),
      checked_at: check.checked_at
    }

    case AppRepo.insert(struct(CheckFailure, attrs)) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  def record(_check), do: :noop

  @doc """
  Fetches recent DOWN-check details for a monitor, keyed by `checked_at`
  (second precision) so callers can merge into metric-sourced rows.
  """
  def recent_for_monitor(monitor_id, limit \\ 20) do
    AppRepo.all(
      from f in CheckFailure,
        where: f.monitor_id == ^monitor_id,
        order_by: [desc: f.checked_at],
        limit: ^limit
    )
  end

  @doc """
  Deletes failure rows older than the given cutoff. Called by the cron job.
  """
  def delete_older_than(%DateTime{} = cutoff) do
    {count, _} =
      AppRepo.delete_all(
        from f in CheckFailure, where: f.checked_at < ^cutoff
      )

    count
  end

  defp truncate(nil, _), do: nil
  defp truncate(str, max) when is_binary(str) do
    if byte_size(str) > max, do: binary_part(str, 0, max), else: str
  end
  defp truncate(_, _), do: nil

  # Only keep useful headers; drop cookies & auth, cap to a small set
  @notable_headers ~w(
    content-type content-length server x-powered-by cache-control x-cache
    cf-ray cf-cache-status x-vercel-cache x-served-by via age
    strict-transport-security location retry-after
  )
  defp sanitize_headers(nil), do: nil
  defp sanitize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {to_string(k) |> String.downcase(), to_string(v)} end)
    |> Map.take(@notable_headers)
    |> case do
      m when map_size(m) == 0 -> nil
      m -> m
    end
  end
  defp sanitize_headers(_), do: nil
end
