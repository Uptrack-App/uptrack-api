defmodule Uptrack.AbusePrevention.DisposableEmailWorker do
  @moduledoc """
  Oban cron worker that refreshes the disposable email domain list daily.

  Fetches from GitHub's disposable/disposable-email-domains repo
  and stores in Nebulex cache for fast O(1) lookups.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @source_url "https://raw.githubusercontent.com/disposable/disposable-email-domains/master/domains.txt"

  @impl Oban.Worker
  def perform(_job) do
    case Req.get(@source_url, retry: false, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        domains =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
          |> MapSet.new()

        Uptrack.AbusePrevention.put_domains(domains)
        Logger.info("DisposableEmailWorker: refreshed #{MapSet.size(domains)} domains")
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("DisposableEmailWorker: GitHub returned #{status}")
        :ok

      {:error, reason} ->
        Logger.warning("DisposableEmailWorker: fetch failed: #{inspect(reason)}")
        # Return :ok to not retry on transient network issues — compile-time fallback still works
        :ok
    end
  end
end
