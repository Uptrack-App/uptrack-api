defmodule Uptrack.Monitoring.GunConnection do
  @moduledoc """
  Manages a Gun HTTP connection lifecycle.

  Organized around the Gun connection data — all Gun-related
  functions live here. MonitorProcess delegates to this module.

  ## Elixir Principles
  - Principle of Attraction: module owns all Gun connection data + functions
  - Small, focused functions: open, close, connected, disconnected
  - Let it crash: Gun process crashes are detected via Process.monitor
  """

  defstruct [:pid, :ref, :host, :port, :tls?, state: :disconnected]

  @type t :: %__MODULE__{
    pid: pid() | nil,
    ref: reference() | nil,
    host: charlist(),
    port: integer(),
    tls?: boolean(),
    state: :connecting | :connected | :disconnected
  }

  @doc "Opens a Gun connection to the target URL."
  @spec open(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(url, opts \\ []) do
    uri = URI.parse(url)
    host = String.to_charlist(uri.host || "localhost")
    port = uri.port || if(uri.scheme == "https", do: 443, else: 80)
    tls? = uri.scheme == "https"

    gun_opts = build_opts(tls?, opts)

    case :gun.open(host, port, gun_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {:ok, %__MODULE__{
          pid: pid, ref: ref,
          host: host, port: port,
          tls?: tls?, state: :connecting
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Closes the Gun connection."
  @spec close(t()) :: :ok
  def close(%__MODULE__{pid: nil}), do: :ok
  def close(%__MODULE__{pid: pid}) do
    :gun.close(pid)
    :ok
  end

  @doc "Marks connection as up."
  def connected(%__MODULE__{} = conn), do: %{conn | state: :connected}

  @doc "Marks connection as down."
  def disconnected(%__MODULE__{} = conn), do: %{conn | state: :disconnected}

  @doc "Checks if connection is ready."
  def connected?(%__MODULE__{state: :connected}), do: true
  def connected?(_), do: false

  # --- Private: build Gun options ---

  defp build_opts(true = _tls?, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    %{
      connect_timeout: timeout,
      retry: 5,
      retry_timeout: 5_000,
      protocols: [:http],
      transport: :tls,
      tls_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    }
  end

  defp build_opts(false, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    %{
      connect_timeout: timeout,
      retry: 5,
      retry_timeout: 5_000,
      protocols: [:http]
    }
  end
end
