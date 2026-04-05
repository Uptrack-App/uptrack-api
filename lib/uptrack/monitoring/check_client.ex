defmodule Uptrack.Monitoring.CheckClient do
  @moduledoc """
  Behaviour for HTTP check implementations.

  Allows swapping between Gun (persistent), Finch (pooled),
  and Mock (tests) without changing MonitorProcess.

  ## Elixir Principles
  - Behaviours for dependency inversion (testability)
  - Config-based injection: `Application.compile_env(:uptrack, :check_client)`
  """

  alias Uptrack.Monitoring.Monitor

  @type check_result :: %{
    status: String.t(),
    status_code: integer() | nil,
    response_time: integer(),
    response_headers: map(),
    response_body: String.t() | nil,
    error_message: String.t() | nil,
    checked_at: DateTime.t(),
    monitor_id: String.t()
  }

  @callback check(monitor :: Monitor.t(), conn :: term()) :: check_result()
  @callback open_connection(monitor :: Monitor.t()) :: {:ok, term()} | {:error, term()}
  @callback close_connection(conn :: term()) :: :ok
end
