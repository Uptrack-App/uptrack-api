defmodule Uptrack.Integrations.OAuthState do
  @moduledoc """
  In-memory storage for OAuth state tokens (CSRF protection).

  Uses ETS for fast, concurrent access with automatic expiration.
  State tokens are single-use and expire after 10 minutes.
  """

  use GenServer

  @table_name :oauth_states
  @cleanup_interval :timer.minutes(5)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Stores an OAuth state token with associated data.
  """
  def store(state, data) when is_binary(state) and is_map(data) do
    :ets.insert(@table_name, {state, data})
    :ok
  end

  @doc """
  Retrieves and deletes an OAuth state token.

  Returns nil if not found (single-use tokens).
  """
  def get_and_delete(state) when is_binary(state) do
    case :ets.lookup(@table_name, state) do
      [{^state, data}] ->
        :ets.delete(@table_name, state)
        data

      [] ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer Implementation
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Create ETS table owned by this process
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired do
    now = DateTime.utc_now()

    # Select and delete expired entries
    :ets.foldl(
      fn {state, %{expires_at: expires_at}}, acc ->
        if DateTime.compare(now, expires_at) != :lt do
          :ets.delete(@table_name, state)
        end
        acc
      end,
      :ok,
      @table_name
    )
  end
end
