## ADDED Requirements

### Requirement: Failure-writer contract defined as an Elixir behaviour
The system SHALL define `Uptrack.Failures` as an Elixir `@behaviour` with a single callback `record/1` that accepts an `Uptrack.Failures.Event` struct and returns `:ok` on enqueue success or `{:error, term()}` on failure. Concrete backends SHALL implement this behaviour.

#### Scenario: Adapter is resolved from application config
- **WHEN** `Uptrack.Failures.record/1` is called at runtime
- **THEN** the caller resolves the active adapter via `Application.get_env(:uptrack, :failures_adapter)`
- **AND** delegates to that module's `record/1` implementation

#### Scenario: Multiple adapters coexist
- **WHEN** the configured adapter is `Uptrack.Failures.DualAdapter`
- **THEN** the event SHALL be written to both the Postgres adapter and the VictoriaLogs adapter
- **AND** Postgres write is durable (synchronous within the caller's `Task`)
- **AND** VL write is fire-and-forget (spawned under `Uptrack.TaskSupervisor`)

### Requirement: Fire-and-forget write semantics
The system SHALL never block a monitor's check pipeline on a forensic-event write. Writes SHALL be executed in a supervised Task outside the caller's process, and write failures SHALL be logged at `:warn` level without propagating to the caller.

#### Scenario: VL unreachable does not stall checks
- **GIVEN** the local vlagent process is unresponsive
- **WHEN** `MonitorProcess` calls `Uptrack.Failures.record/1` on a DOWN check
- **THEN** the call returns `:ok` immediately
- **AND** the check pipeline continues processing subsequent results

#### Scenario: Postgres adapter write failure is logged, not raised
- **WHEN** `Uptrack.Failures.PostgresAdapter.record/1` encounters a DB error
- **THEN** the error is logged at `:warn`
- **AND** the function returns `{:error, reason}` without raising

### Requirement: Per-monitor fingerprint dedup in MonitorProcess
The system SHALL deduplicate consecutive failure events with identical fingerprints by storing the last-emitted fingerprint per monitor in the owning `Uptrack.Monitoring.MonitorProcess` GenServer's state. A fingerprint is the tuple `{status_code, error_class, body_sha256}`.

#### Scenario: Identical consecutive failures are deduplicated
- **GIVEN** `MonitorProcess` emitted a failure event 3 minutes ago with fingerprint F
- **WHEN** a new DOWN check produces the same fingerprint F
- **THEN** no new event is emitted to `Uptrack.Failures`
- **AND** the DB counter `consecutive_failures` is still incremented

#### Scenario: Fingerprint change triggers a new event
- **GIVEN** `MonitorProcess` emitted a failure event with fingerprint F1
- **WHEN** a new DOWN check produces a different fingerprint F2
- **THEN** a new failure event is emitted to `Uptrack.Failures`
- **AND** the in-memory `last_failure_fingerprint` is updated to F2

#### Scenario: 10-minute ceiling forces re-emission
- **GIVEN** `MonitorProcess` emitted a failure event more than 10 minutes ago
- **WHEN** a new DOWN check produces the same fingerprint
- **THEN** a new event is emitted regardless of fingerprint match

#### Scenario: First failure after process restart always emits
- **GIVEN** a `MonitorProcess` has just been initialized via `init/1`
- **AND** `last_failure_fingerprint` is nil
- **WHEN** the first DOWN check is processed
- **THEN** a failure event is emitted
- **AND** the state is updated with the new fingerprint

### Requirement: Lifecycle events always emit
The system SHALL emit a failure event on every incident lifecycle transition regardless of fingerprint dedup. Lifecycle transitions include: `incident_created`, `incident_upgraded` (degraded→down), `incident_resolved`.

#### Scenario: Incident creation event bypasses dedup
- **WHEN** `MonitorProcess` creates a new incident
- **THEN** a lifecycle event with `event_type: "incident_created"` SHALL be emitted regardless of `last_failure_fingerprint`
- **AND** the event carries the incident's `vl_trace_id`

#### Scenario: Resolution event bypasses dedup
- **WHEN** `MonitorProcess` resolves an incident via the UP path
- **THEN** a lifecycle event with `event_type: "incident_resolved"` SHALL be emitted
- **AND** the event carries the same `vl_trace_id` as the creation event

### Requirement: Sharded batcher with per-shard persistent Gun connection
The system SHALL route forensic events through a Batcher supervisor (`Uptrack.Failures.Batcher`) composed of N shard GenServers. Each shard SHALL own one long-lived Gun connection to `localhost:9429` and MUST NOT rely on a shared HTTP connection pool. Events are assigned to a shard by `:erlang.phash2(monitor_id, shard_count)`.

#### Scenario: Events with the same monitor_id always land on the same shard
- **WHEN** two events for monitor M are written at different times
- **THEN** `:erlang.phash2(M, shard_count)` returns the same shard index both times
- **AND** both events are enqueued on the same shard's GenServer mailbox

#### Scenario: Shard count defaults to schedulers_online
- **WHEN** the application starts without `:failures_shard_count` config
- **THEN** the Batcher supervisor starts `System.schedulers_online()` named shard processes

#### Scenario: Each shard has exactly one Gun connection
- **GIVEN** a running shard GenServer
- **WHEN** its state is inspected
- **THEN** `state.conn` holds exactly one `:gun` pid (or `nil` if the connection is being re-established)

### Requirement: Batch flush on size, byte, or time threshold
Each shard SHALL flush its buffer on the first of these conditions: 1000 buffered lines, 1 MB of buffered bytes, or 1 second since the last flush. A flush SHALL send the buffered NDJSON payload as a single `:gun.post/4` call.

#### Scenario: Flush triggered by line count
- **GIVEN** a shard has accumulated 999 buffered events
- **WHEN** a 1000th event arrives
- **THEN** the shard issues exactly one `:gun.post/4` call whose body contains all 1000 NDJSON lines
- **AND** the buffer is reset to empty

#### Scenario: Flush triggered by byte budget
- **GIVEN** a shard has buffered events totaling just under 1 MB
- **WHEN** the next event pushes total bytes to ≥ 1 MB
- **THEN** the shard issues one `:gun.post/4` call with the buffered payload

#### Scenario: Flush triggered by timer
- **GIVEN** a shard has at least one buffered event and no size/byte threshold has fired
- **WHEN** 1 second has elapsed since the last flush
- **THEN** the shard issues one `:gun.post/4` call with whatever is buffered
- **AND** the timer is rescheduled for 1 second later

### Requirement: Drop-oldest on overflow
When a shard's buffer exceeds 5000 lines OR 5 MB, the shard SHALL discard the oldest buffered events to make room for new ones. A counter metric SHALL record the number of dropped events so observability can alert on sustained drops.

#### Scenario: Overflow drops the oldest events
- **GIVEN** a shard with 5000 buffered lines
- **WHEN** a new event arrives before the next flush
- **THEN** the oldest event in the buffer is discarded
- **AND** the new event is appended
- **AND** `uptrack_forensic_events_dropped_total` counter is incremented by 1

### Requirement: Gun connection auto-recovers without blocking writers
When a shard's Gun connection goes down (`:gun_down` message), the shard SHALL continue to accept writes into its buffer. Gun's built-in reconnect SHALL re-establish the connection without external intervention. Buffered events SHALL flush on the next successful connection up.

#### Scenario: Disconnect does not drop writes immediately
- **GIVEN** a shard receives `{:gun_down, conn, _, _, _}`
- **WHEN** new events are cast to the shard
- **THEN** they are appended to the buffer as normal
- **AND** no `:gun.post/4` call is attempted until `:gun_up` is received

#### Scenario: Reconnect flushes buffered events
- **GIVEN** a shard buffered N events during a Gun-down window
- **WHEN** `{:gun_up, conn, _}` arrives
- **THEN** the next flush-trigger sends all buffered events in one batch

### Requirement: VictoriaLogs stream field policy
The system's `VictoriaLogsAdapter` SHALL use `monitor_id` as the sole stream field when writing to VL. All other fields SHALL be regular (queryable but not stream-defining).

#### Scenario: Stream field is monitor_id only
- **WHEN** `VictoriaLogsAdapter.record/1` composes the NDJSON payload
- **THEN** the `_stream_fields` JSON value SHALL contain exactly `["monitor_id"]`
- **AND** fields like `status_code`, `region`, and `organization_id` SHALL NOT appear in `_stream_fields`

### Requirement: Response-body truncation and hashing
The system SHALL truncate response bodies to 64 KB before sending to VL. The full SHA256 of the pre-truncation body SHALL be included in every failure event.

#### Scenario: Body under 64 KB is stored verbatim
- **GIVEN** a DOWN check with a 4 KB response body
- **WHEN** the event is composed
- **THEN** the `body` field contains the full 4 KB
- **AND** `body_truncated: false`
- **AND** `body_bytes_total: 4096`
- **AND** `body_sha256` contains the hex-encoded SHA256 of the 4 KB body

#### Scenario: Body over 64 KB is truncated and flagged
- **GIVEN** a DOWN check with a 200 KB response body
- **WHEN** the event is composed
- **THEN** the `body` field contains the first 65536 bytes
- **AND** `body_truncated: true`
- **AND** `body_bytes_total: 204800`
- **AND** `body_sha256` is computed over the full 200 KB, not the truncated payload

### Requirement: Incidents carry a VictoriaLogs trace pointer
The system SHALL store a uuid v7 `vl_trace_id` on every incident row at creation time. All lifecycle events for that incident SHALL carry the same `trace_id`.

#### Scenario: vl_trace_id is generated at incident creation
- **WHEN** `Monitoring.create_incident/1` inserts a new incident
- **THEN** the row has a non-null `vl_trace_id` column value
- **AND** the value is a valid uuid v7

#### Scenario: Lifecycle events share the incident's trace_id
- **GIVEN** an incident with `vl_trace_id: T`
- **WHEN** the incident is upgraded (degraded → down) or resolved
- **THEN** the emitted VL event's `trace_id` field equals `T`

### Requirement: Incident detail API fetches forensic from VictoriaLogs
The system SHALL expose an endpoint `GET /api/incidents/:id/forensic` that returns the chronologically ordered VL events associated with the incident's `vl_trace_id`. The endpoint SHALL fall back gracefully when forensic data is unavailable.

#### Scenario: Forensic data present
- **GIVEN** an incident with `vl_trace_id: T` and events present in VL
- **WHEN** `GET /api/incidents/:id/forensic` is called
- **THEN** the response status is 200
- **AND** the body contains an array of events ordered by event timestamp ascending

#### Scenario: Forensic data missing (pre-retention incident)
- **GIVEN** an incident whose `vl_trace_id` is older than VL's retention period
- **WHEN** the endpoint is called
- **THEN** the response status is 200
- **AND** the body contains `{"events": [], "forensic_available": false}`

#### Scenario: VL unreachable
- **GIVEN** VL is down or unreachable from the app node
- **WHEN** the endpoint is called
- **THEN** the response status is 503
- **AND** the body indicates temporary forensic unavailability
- **AND** the failure is logged at `:warn`

### Requirement: Check failures emit VM counter + histogram
The system SHALL emit `uptrack_check_failures_total{monitor_id, status_code, region}` counter and `uptrack_check_duration_ms{monitor_id, status, region}` histogram on every check, routed through the existing vmagent pipeline. These metrics are independent of forensic events and are NOT subject to dedup.

#### Scenario: Every DOWN check increments the counter
- **WHEN** a DOWN check is persisted by `CheckWorker`
- **THEN** `uptrack_check_failures_total` is incremented by 1 with labels set from the check
- **AND** the increment fires whether or not the forensic event was deduplicated

#### Scenario: Every check records a duration sample
- **WHEN** any check (UP or DOWN) is persisted
- **THEN** the duration is recorded to `uptrack_check_duration_ms` with the appropriate `status` label
