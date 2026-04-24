defmodule Uptrack.Failures.Event do
  @moduledoc """
  Immutable value struct describing a single forensic event.

  One struct flows through the `Uptrack.Failures` behaviour regardless
  of whether the backend writes to Postgres, VictoriaLogs, or both.
  Adapters may drop fields they don't persist.

  Construction is done via:

    * `new_from_check/3` — for check-triggered failures (DOWN path).
    * `new_lifecycle/3` — for incident lifecycle transitions.

  Both helpers apply body truncation to 64 KB and fill `body_sha256`
  with the hash of the pre-truncation body.
  """

  alias Uptrack.Failures.Fingerprint
  alias Uptrack.Monitoring.{Monitor, MonitorCheck}

  @body_cap_bytes 64 * 1024

  @enforce_keys [:monitor_id, :organization_id, :event_type, :occurred_at]
  defstruct [
    :monitor_id,
    :organization_id,
    :incident_id,
    :trace_id,
    :event_type,
    :occurred_at,
    :status_code,
    :response_time_ms,
    :error_class,
    :error_message,
    :region,
    :fingerprint,
    :body,
    :body_bytes_total,
    :body_sha256,
    :body_truncated,
    :response_headers,
    :tls,
    :redirect_chain,
    :assertions,
    :consensus,
    :monitor_type,
    :monitor_url
  ]

  @type event_type ::
          :check_failed
          | :state_change_down
          | :state_change_up
          | :incident_created
          | :incident_upgraded
          | :incident_resolved

  @type t :: %__MODULE__{
          monitor_id: String.t(),
          organization_id: String.t(),
          incident_id: String.t() | nil,
          trace_id: String.t() | nil,
          event_type: event_type(),
          occurred_at: DateTime.t(),
          status_code: integer() | nil,
          response_time_ms: integer() | nil,
          error_class: Fingerprint.error_class() | nil,
          error_message: String.t() | nil,
          region: String.t() | nil,
          fingerprint: Fingerprint.t() | nil,
          body: String.t() | nil,
          body_bytes_total: non_neg_integer() | nil,
          body_sha256: String.t() | nil,
          body_truncated: boolean() | nil,
          response_headers: map() | nil,
          tls: map() | nil,
          redirect_chain: list(String.t()) | nil,
          assertions: list(map()) | nil,
          consensus: map() | nil,
          monitor_type: String.t() | nil,
          monitor_url: String.t() | nil
        }

  @doc """
  Builds an event from a `MonitorCheck` struct on the DOWN path.
  The `:event_type` defaults to `:check_failed`; callers pass
  `:state_change_down` or `:state_change_up` when appropriate.
  """
  @spec new_from_check(MonitorCheck.t(), Monitor.t(), keyword()) :: t()
  def new_from_check(%MonitorCheck{} = check, %Monitor{} = monitor, opts \\ []) do
    {body, truncated?, total_bytes} = truncate_body(check.response_body)
    sha = Fingerprint.body_sha256(check.response_body)
    fingerprint = Fingerprint.compute(check)

    %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      incident_id: Keyword.get(opts, :incident_id),
      trace_id: Keyword.get(opts, :trace_id),
      event_type: Keyword.get(opts, :event_type, :check_failed),
      occurred_at: check.checked_at || DateTime.utc_now(),
      status_code: check.status_code,
      response_time_ms: check.response_time,
      error_class: elem(fingerprint, 1),
      error_message: check.error_message,
      region: Keyword.get(opts, :region),
      fingerprint: fingerprint,
      body: body,
      body_bytes_total: total_bytes,
      body_sha256: sha,
      body_truncated: truncated?,
      response_headers: check.response_headers,
      tls: Keyword.get(opts, :tls),
      redirect_chain: Keyword.get(opts, :redirect_chain),
      assertions: Keyword.get(opts, :assertions),
      consensus: Keyword.get(opts, :consensus),
      monitor_type: monitor.monitor_type,
      monitor_url: monitor.url
    }
  end

  @doc """
  Builds a lifecycle event (incident created/upgraded/resolved).
  Lifecycle events bypass the fingerprint dedup at the caller.
  """
  @spec new_lifecycle(event_type(), Monitor.t(), keyword()) :: t()
  def new_lifecycle(event_type, %Monitor{} = monitor, opts \\ [])
      when event_type in [:incident_created, :incident_upgraded, :incident_resolved] do
    %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      incident_id: Keyword.get(opts, :incident_id),
      trace_id: Keyword.get(opts, :trace_id),
      event_type: event_type,
      occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now()),
      status_code: Keyword.get(opts, :status_code),
      response_time_ms: Keyword.get(opts, :response_time_ms),
      error_class: Keyword.get(opts, :error_class),
      error_message: Keyword.get(opts, :error_message),
      region: Keyword.get(opts, :region),
      monitor_type: monitor.monitor_type,
      monitor_url: monitor.url
    }
  end

  @spec truncate_body(binary() | nil) ::
          {truncated :: binary() | nil, truncated? :: boolean(), total_bytes :: non_neg_integer()}
  defp truncate_body(nil), do: {nil, false, 0}
  defp truncate_body(""), do: {"", false, 0}

  defp truncate_body(body) when is_binary(body) do
    total = byte_size(body)

    if total > @body_cap_bytes do
      {binary_part(body, 0, @body_cap_bytes), true, total}
    else
      {body, false, total}
    end
  end

  defp truncate_body(_), do: {nil, false, 0}

  @doc "Exposes the body cap for tests and for consumers that want to match."
  def body_cap_bytes, do: @body_cap_bytes
end
