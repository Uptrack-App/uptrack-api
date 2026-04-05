defmodule Uptrack.Tools.WebsiteChecker do
  @moduledoc """
  Public "Is Website Down?" tool.

  Performs a one-time HTTP check from all connected regions
  and returns per-region results. Used by the free public tool.
  """

  require Logger

  @timeout 15_000
  @regions %{
    "europe" => "Nuremberg, DE",
    "us" => "Ashburn, US",
    "asia" => "Hyderabad, IN"
  }

  @doc """
  Checks a URL from all available regions.
  Returns a list of region results.
  """
  def check(url) do
    url = normalize_url(url)

    # Local check (this node's region)
    local_region = Application.get_env(:uptrack, :node_region, "europe")
    local_task = Task.async(fn -> {local_region, do_check(url)} end)

    # Remote checks on worker nodes (call UptrackWorker.Tools.check_website/1)
    remote_tasks =
      Node.list()
      |> Enum.filter(&worker_node?/1)
      |> Enum.map(fn node ->
        Task.async(fn ->
          try do
            :erpc.call(node, UptrackWorker.Tools, :check_website, [url], @timeout + 2_000)
          catch
            _, reason ->
              region = extract_region_from_node(node)
              {region, %{status: "error", error: "Node unreachable: #{inspect(reason)}"}}
          end
        end)
      end)

    # Collect all results
    all_tasks = [local_task | remote_tasks]

    results =
      Task.yield_many(all_tasks, @timeout + 5_000)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, {region, data}} -> Map.merge(data, %{region: region, location: @regions[region] || region})
          _ ->
            Task.shutdown(task, :brutal_kill)
            %{region: "unknown", location: "Unknown", status: "timeout", response_time: 0, error: "Check timed out"}
        end
      end)
      |> Enum.uniq_by(& &1.region)

    %{url: url, results: results, checked_at: DateTime.utc_now()}
  end

  @doc "Performs a check and returns {region, result}. Called via :erpc from main app."
  def do_check_with_region(url) do
    region = Application.get_env(:uptrack_worker, :node_region, "unknown")
    {region, do_check(url)}
  end

  @doc "Performs a single HTTP check against a URL using Mint."
  def do_check(url) do
    start_time = System.monotonic_time(:millisecond)

    try do
      uri = URI.parse(url)
      scheme = if uri.scheme == "https", do: :https, else: :http
      host = uri.host || "localhost"
      port = uri.port || if(scheme == :https, do: 443, else: 80)
      path = (uri.path || "/") <> if(uri.query, do: "?#{uri.query}", else: "")

      case Mint.HTTP.connect(scheme, host, port,
             transport_opts: [verify: :verify_none],
             timeout: @timeout) do
        {:ok, conn} ->
          case Mint.HTTP.request(conn, "GET", path, [{"host", host}, {"user-agent", "Uptrack Checker/1.0"}], nil) do
            {:ok, conn, ref} ->
              {conn, status, _body} = collect_mint_response(conn, ref, @timeout)
              response_time = System.monotonic_time(:millisecond) - start_time
              Mint.HTTP.close(conn)

              %{
                status: if(status && status < 400, do: "up", else: "down"),
                status_code: status,
                response_time: response_time
              }

            {:error, conn, reason} ->
              Mint.HTTP.close(conn)
              response_time = System.monotonic_time(:millisecond) - start_time
              %{status: "down", response_time: response_time, error: inspect(reason)}
          end

        {:error, reason} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          %{status: "down", response_time: response_time, error: inspect(reason)
          }
      end
    rescue
      e ->
        response_time = System.monotonic_time(:millisecond) - start_time
        %{status: "down", response_time: response_time, error: Exception.message(e)}
    end
  end

  defp collect_mint_response(conn, ref, timeout) do
    collect_mint_response(conn, ref, timeout, nil, [])
  end

  defp collect_mint_response(conn, ref, timeout, status, body_parts) do
    receive do
      msg ->
        case Mint.HTTP.stream(conn, msg) do
          {:ok, conn, responses} ->
            {status, body_parts, done?} =
              Enum.reduce(responses, {status, body_parts, false}, fn
                {:status, ^ref, s}, {_, b, _} -> {s, b, false}
                {:headers, ^ref, _}, acc -> acc
                {:data, ^ref, d}, {s, b, _} -> {s, [d | b], false}
                {:done, ^ref}, {s, b, _} -> {s, b, true}
                _, acc -> acc
              end)

            if done? do
              {conn, status, body_parts |> Enum.reverse() |> IO.iodata_to_binary()}
            else
              collect_mint_response(conn, ref, timeout, status, body_parts)
            end

          {:error, conn, _reason, _} -> {conn, nil, ""}
          :unknown -> collect_mint_response(conn, ref, timeout, status, body_parts)
        end
    after
      timeout -> {conn, nil, ""}
    end
  end

  defp normalize_url(url) do
    url = String.trim(url)

    cond do
      String.starts_with?(url, "http://") -> url
      String.starts_with?(url, "https://") -> url
      true -> "https://#{url}"
    end
  end

  defp worker_node?(node) do
    node_str = Atom.to_string(node)
    String.starts_with?(node_str, "uptrack_worker@")
  end

  defp extract_region_from_node(node) do
    try do
      :erpc.call(node, Application, :get_env, [:uptrack_worker, :node_region, "unknown"], 3_000)
    catch
      _, _ -> "unknown"
    end
  end
end
