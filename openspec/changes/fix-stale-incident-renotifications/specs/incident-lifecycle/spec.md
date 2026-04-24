## ADDED Requirements

### Requirement: Single ongoing incident per monitor
The system SHALL have at most one `ongoing` incident row per monitor at any time. The `incidents_one_ongoing_per_monitor_idx` partial unique index enforces this at the database level.

#### Scenario: Concurrent create attempts
- **WHEN** two code paths (e.g. `MonitorProcess` and `check_worker` Oban job) call `Monitoring.create_incident/1` for the same monitor in parallel and neither sees an existing `ongoing` row
- **THEN** the database accepts exactly one insert and rejects the other via the unique index

#### Scenario: Create attempt with existing ongoing
- **WHEN** `Monitoring.create_incident/1` is called for a monitor that already has an `ongoing` incident
- **THEN** the function returns `{:error, :already_ongoing}`
- **AND** no new row is inserted

### Requirement: No alerts on duplicate-create suppression
The system SHALL NOT broadcast `incident_created` events or dispatch "monitor down" alerts when a `create_incident` call is rejected as a duplicate of an existing `ongoing` incident.

#### Scenario: Duplicate suppressed in check_worker
- **WHEN** `Uptrack.Monitoring.CheckWorker` receives `{:error, :already_ongoing}` from `create_incident/1`
- **THEN** it logs at info level
- **AND** it does NOT call `Events.broadcast_incident_created/2`
- **AND** it does NOT call `Alerting.send_incident_alerts/2`
- **AND** it does NOT call `Alerting.notify_subscribers_incident/2`

#### Scenario: Duplicate suppressed in MonitorProcess
- **WHEN** `Uptrack.Monitoring.MonitorProcess` receives `{:error, :already_ongoing}` from `create_incident/1`
- **THEN** it logs at info level
- **AND** it does NOT call `Events.broadcast_incident_created/2`
- **AND** it does NOT call `Uptrack.Alerting.send_incident_alerts/2`
- **AND** it does NOT call `Uptrack.Alerting.notify_subscribers_incident/2`

### Requirement: MonitorProcess state hydrates from DB at init
The system SHALL initialize each `Uptrack.Monitoring.MonitorProcess` with in-memory state that reflects the current `incidents` table, so that after any restart the next successful check resolves existing `ongoing` incidents rather than orphaning them.

#### Scenario: Init with existing ongoing incident
- **WHEN** a `MonitorProcess` starts and `Monitoring.get_ongoing_incident(monitor.id)` returns an incident
- **THEN** the process state has `alerted_this_streak: true`
- **AND** `incident_id` set to the existing incident's id
- **AND** `consecutive_failures` set to `monitor.confirmation_threshold` (or its default of 3 when nil)

#### Scenario: Init with no ongoing incident
- **WHEN** a `MonitorProcess` starts and `Monitoring.get_ongoing_incident(monitor.id)` returns `nil`
- **THEN** the process state has `alerted_this_streak: false`
- **AND** `incident_id: nil`
- **AND** `consecutive_failures: 0`

### Requirement: Ongoing incidents resolve on next UP check after restart
The system SHALL resolve each `ongoing` incident on the monitor's next successful check, even if the process that created the incident has since died and been replaced.

#### Scenario: Recovered monitor resolves stale incident after restart
- **GIVEN** a monitor has an `ongoing` incident in the DB from before the Phoenix app was last restarted
- **WHEN** the restarted `MonitorProcess` executes a check that returns status `up`
- **THEN** `Monitoring.resolve_all_ongoing_incidents(monitor.id)` is called
- **AND** the incident is updated to status `resolved` with `resolved_at` set to the current time
- **AND** a single resolution alert is dispatched to subscribed channels

#### Scenario: No resolution alert when nothing to resolve
- **GIVEN** a monitor has no `ongoing` incidents in the DB
- **WHEN** the `MonitorProcess` executes a check that returns status `up`
- **THEN** no resolution alert is dispatched
