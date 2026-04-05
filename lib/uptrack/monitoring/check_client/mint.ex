defmodule Uptrack.Monitoring.CheckClient.Mint do
  @moduledoc """
  Mint-based HTTP check client. Process-less persistent connections.
  3.9x less RAM per connection vs Gun.
  """

  @behaviour Uptrack.Monitoring.CheckClient

  alias Uptrack.Monitoring.MintConnection

  @impl true
  def open_connection(%{url: url, timeout: timeout}) do
    MintConnection.open(url, timeout: (timeout || 30) * 1000)
  end

  def open_connection(monitor) do
    MintConnection.open(monitor.url, timeout: (Map.get(monitor, :timeout, 30)) * 1000)
  end

  @impl true
  def close_connection(%MintConnection{} = mc), do: MintConnection.close(mc)
  def close_connection(_), do: :ok

  @impl true
  def check(monitor, %MintConnection{} = mc) do
    request = build_request(monitor)
    start_time = System.monotonic_time(:millisecond)
    timeout = (Map.get(monitor, :timeout, 30)) * 1000

    case MintConnection.request(mc, request.method, request.path, request.headers) do
      {:ok, mc, ref} ->
        case collect_response(mc, ref, timeout) do
          {:ok, mc, status, headers, body} ->
            response_time = System.monotonic_time(:millisecond) - start_time
            result = build_check_attrs(monitor, {:ok, status, headers, body}, response_time)
            Map.put(result, :__mint_conn__, mc)

          {:error, mc, reason} ->
            response_time = System.monotonic_time(:millisecond) - start_time
            result = build_check_attrs(monitor, {:error, reason}, response_time)
            Map.put(result, :__mint_conn__, mc)
        end

      {:error, mc, reason} ->
        %{
          monitor_id: monitor.id, status: "down", response_time: 0,
          checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
          error_message: "Connection error: #{inspect(reason)}",
          __mint_conn__: mc
        }
    end
  end

  def check(monitor, _conn) do
    %{
      monitor_id: monitor.id, status: "down", response_time: 0,
      checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      error_message: "No connection to target host"
    }
  end

  defp collect_response(mc, ref, timeout) do
    collect_response(mc, ref, timeout, nil, [], [])
  end

  defp collect_response(mc, ref, timeout, status, headers, body_parts) do
    receive do
      msg ->
        case MintConnection.stream(mc, msg) do
          {:ok, mc, responses} ->
            {status, headers, body_parts, done?} =
              Enum.reduce(responses, {status, headers, body_parts, false}, fn
                {:status, ^ref, s}, {_, h, b, _} -> {s, h, b, false}
                {:headers, ^ref, h}, {s, _, b, _} -> {s, h, b, false}
                {:data, ^ref, d}, {s, h, b, _} -> {s, h, [d | b], false}
                {:done, ^ref}, {s, h, b, _} -> {s, h, b, true}
                _, acc -> acc
              end)

            if done? do
              body = body_parts |> Enum.reverse() |> IO.iodata_to_binary()
              {:ok, mc, status, headers, body}
            else
              collect_response(mc, ref, timeout, status, headers, body_parts)
            end

          {:error, mc, reason, _} -> {:error, mc, reason}
          :unknown -> collect_response(mc, ref, timeout, status, headers, body_parts)
        end
    after
      timeout -> {:error, mc, :timeout}
    end
  end

  # Pure functions — delegate to Gun impl (identical logic)
  defp build_request(monitor), do: Uptrack.Monitoring.CheckClient.Gun.build_request(monitor)
  defp build_check_attrs(monitor, result, rt), do: Uptrack.Monitoring.CheckClient.Gun.build_check_attrs(monitor, result, rt)
end
