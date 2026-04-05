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

    # Remote checks on worker nodes
    remote_tasks =
      Node.list()
      |> Enum.filter(&worker_node?/1)
      |> Enum.map(fn node ->
        Task.async(fn ->
          try do
            :erpc.call(node, __MODULE__, :do_check_with_region, [url], @timeout + 2_000)
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

  @doc "Performs a single HTTP check against a URL."
  def do_check(url) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        Req.get(url,
          connect_options: [timeout: @timeout],
          receive_timeout: @timeout,
          redirect: true,
          max_redirects: 5,
          retry: false
        )

      response_time = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, resp} ->
          %{
            status: if(resp.status < 400, do: "up", else: "down"),
            status_code: resp.status,
            response_time: response_time
          }

        {:error, %{reason: reason}} ->
          %{
            status: "down",
            response_time: response_time,
            error: to_string(reason)
          }
      end
    rescue
      e ->
        response_time = System.monotonic_time(:millisecond) - start_time
        %{status: "down", response_time: response_time, error: Exception.message(e)}
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
