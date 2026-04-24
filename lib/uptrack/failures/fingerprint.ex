defmodule Uptrack.Failures.Fingerprint do
  @moduledoc """
  Pure functions for classifying failures and producing stable
  fingerprints used by `MonitorProcess` dedup.

  A fingerprint is the tuple `{status_code, error_class, body_sha256}`.
  Identical fingerprints within the dedup window collapse to a single
  forensic event.
  """

  @type error_class ::
          :dns | :tcp | :tls | :http | :timeout | :assertion | :unknown

  @type t :: {status_code :: integer() | nil, error_class(), body_sha256 :: String.t() | nil}

  @doc """
  Computes the fingerprint tuple from a check result map.

  Accepts either an `%Uptrack.Monitoring.MonitorCheck{}` or a plain map
  carrying the same fields (`status_code`, `error_message`,
  `response_body`).
  """
  @spec compute(map()) :: t()
  def compute(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> compute()
  end

  def compute(map) when is_map(map) do
    status_code = Map.get(map, :status_code)
    error_message = Map.get(map, :error_message)
    body = Map.get(map, :response_body)
    {status_code, error_class(error_message, status_code), body_sha256(body)}
  end

  @doc """
  Classifies an error into a stable error class. Pure heuristic on the
  error message string.
  """
  @spec error_class(String.t() | nil, integer() | nil) :: error_class()
  def error_class(nil, nil), do: :unknown
  def error_class(nil, status) when is_integer(status) and status >= 400, do: :http
  def error_class(nil, _), do: :unknown

  def error_class(message, _status) when is_binary(message) do
    cond do
      message =~ ~r/timeout|timed out/i -> :timeout
      message =~ ~r/nxdomain|dns|resolve/i -> :dns
      message =~ ~r/connection refused|econnrefused|tcp|socket/i -> :tcp
      message =~ ~r/tls|ssl|certificate|cert/i -> :tls
      message =~ ~r/assert/i -> :assertion
      true -> :http
    end
  end

  def error_class(_, _), do: :unknown

  @doc """
  Returns the hex-encoded SHA256 of a response body. Nil body hashes to
  nil so the fingerprint collapses body-less errors together.
  """
  @spec body_sha256(binary() | nil) :: String.t() | nil
  def body_sha256(nil), do: nil
  def body_sha256(""), do: nil

  def body_sha256(body) when is_binary(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  def body_sha256(_), do: nil
end
