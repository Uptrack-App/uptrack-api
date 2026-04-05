defmodule Uptrack.Monitoring.MintConnection do
  @moduledoc """
  Manages a Mint HTTP connection lifecycle.
  Process-less — connection is a struct stored in GenServer state.
  """

  defstruct [:conn, :host, :port, :scheme, state: :disconnected]

  @type t :: %__MODULE__{
          conn: Mint.HTTP.t() | nil,
          host: String.t(),
          port: integer(),
          scheme: :http | :https,
          state: :connected | :disconnected
        }

  @spec open(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(url, opts \\ []) do
    uri = URI.parse(url)
    scheme = if uri.scheme == "https", do: :https, else: :http
    host = uri.host || "localhost"
    port = uri.port || if(scheme == :https, do: 443, else: 80)
    timeout = Keyword.get(opts, :timeout, 30_000)

    transport_opts =
      if scheme == :https do
        [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3,
         customize_hostname_check: [
           match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
         ]]
      else
        []
      end

    case Mint.HTTP.connect(scheme, host, port,
           transport_opts: transport_opts,
           timeout: timeout) do
      {:ok, conn} ->
        {:ok, %__MODULE__{conn: conn, host: host, port: port, scheme: scheme, state: :connected}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{conn: nil}), do: :ok
  def close(%__MODULE__{conn: conn}) do
    Mint.HTTP.close(conn)
    :ok
  end

  def connected?(%__MODULE__{state: :connected, conn: conn}) when not is_nil(conn), do: true
  def connected?(_), do: false

  def request(%__MODULE__{conn: conn} = mc, method, path, headers) do
    case Mint.HTTP.request(conn, method, path, headers, nil) do
      {:ok, conn, ref} -> {:ok, %{mc | conn: conn}, ref}
      {:error, conn, reason} -> {:error, %{mc | conn: conn, state: :disconnected}, reason}
    end
  end

  def stream(%__MODULE__{conn: conn} = mc, message) do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} -> {:ok, %{mc | conn: conn}, responses}
      {:error, conn, reason, responses} -> {:error, %{mc | conn: conn, state: :disconnected}, reason, responses}
      :unknown -> :unknown
    end
  end

  def disconnected(%__MODULE__{} = mc), do: %{mc | state: :disconnected, conn: nil}
end
