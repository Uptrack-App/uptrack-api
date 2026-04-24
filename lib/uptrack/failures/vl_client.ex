defmodule Uptrack.Failures.VlClient do
  @moduledoc """
  Pure encoding + HTTP query helpers for VictoriaLogs.

  The write path does NOT use this module for HTTP — writes go through
  `Uptrack.Failures.Batcher.Shard` which owns persistent Gun
  connections per destination. This module exposes:

    * `encode/1` — produces a single newline-terminated NDJSON line
      for a `%Uptrack.Failures.Event{}`. Shards concatenate many
      encoded lines and POST them as one batch.

    * `fetch_by_trace_id/2` — reads a forensic trace from either VL
      node (nbg3, then nbg4 on failure). Used by the incident-detail
      API, low request rate, so Req/Finch is fine here.
  """

  require Logger

  @stream_field "monitor_id"

  @doc """
  Encodes a single event into one trailing-newline-terminated JSON
  line. Pure — no side effects, no network.
  """
  @spec encode(Uptrack.Failures.Event.t()) :: binary()
  def encode(%Uptrack.Failures.Event{} = event) do
    event
    |> Map.from_struct()
    |> Map.put(:_msg, "#{event.event_type} #{event.monitor_id}")
    |> Map.put(:_time, DateTime.to_iso8601(event.occurred_at))
    |> Map.update(:event_type, event.event_type, &stringify/1)
    |> Map.update(:error_class, event.error_class, &stringify/1)
    |> Map.update(:fingerprint, event.fingerprint, &stringify_fingerprint/1)
    |> Map.drop([:occurred_at])
    |> drop_nils()
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  @doc "Returns the `_stream_fields` value for insert URLs."
  def stream_fields, do: @stream_field

  @doc """
  Queries VictoriaLogs by (monitor_id, trace_id). Tries each URL in
  order; falls back to the next on any non-2xx or transport error.
  Returns events ordered by their `_time` ascending.
  """
  @spec fetch_by_trace_id(String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def fetch_by_trace_id(monitor_id, trace_id, opts \\ [])

  def fetch_by_trace_id(monitor_id, trace_id, opts)
      when is_binary(monitor_id) and is_binary(trace_id) do
    urls = query_urls(opts)

    query =
      ~s({#{@stream_field}=#{quote_value(monitor_id)}} trace_id:=#{quote_value(trace_id)})

    try_query(urls, query, opts)
  end

  def fetch_by_trace_id(_monitor_id, _trace_id, _opts), do: {:ok, []}

  # --- private ---

  defp try_query([], _query, _opts), do: {:error, :all_urls_unreachable}

  defp try_query([url | rest], query, opts) do
    case Req.get(url,
           params: [query: query, limit: Keyword.get(opts, :limit, 1_000)],
           receive_timeout: Keyword.get(opts, :timeout_ms, 2_000)
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %{status: status}} ->
        Logger.warning("VlClient: #{url} returned #{status}; falling back")
        try_query(rest, query, opts)

      {:error, reason} ->
        Logger.warning("VlClient: #{url} failed: #{inspect(reason)}; falling back")
        try_query(rest, query, opts)
    end
  rescue
    e ->
      Logger.warning("VlClient rescue on #{url}: #{Exception.message(e)}")
      try_query(rest, query, opts)
  end

  defp parse_response(body) when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&safe_decode/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&Map.get(&1, "_time", ""))
  end

  defp parse_response(list) when is_list(list), do: list
  defp parse_response(_), do: []

  defp safe_decode(line) do
    case Jason.decode(line) do
      {:ok, obj} -> obj
      _ -> nil
    end
  end

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp stringify(nil), do: nil
  defp stringify(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify(other), do: other

  defp stringify_fingerprint(nil), do: nil
  defp stringify_fingerprint({code, class, hash}), do: "#{code || "_"}|#{class}|#{hash || "_"}"

  defp quote_value(value) when is_binary(value) do
    if String.contains?(value, [" ", "\"", "{", "}"]) do
      ~s("#{String.replace(value, "\"", "\\\"")}")
    else
      value
    end
  end

  defp query_urls(opts) do
    case Keyword.get(opts, :query_urls) do
      nil ->
        Application.get_env(:uptrack, Uptrack.Failures, [])
        |> Keyword.get(:query_urls, default_query_urls())

      urls when is_list(urls) ->
        urls
    end
  end

  defp default_query_urls do
    [
      "http://100.64.1.3:9428/select/logsql/query",
      "http://100.64.1.4:9428/select/logsql/query"
    ]
  end
end
