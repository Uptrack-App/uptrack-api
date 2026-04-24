## ADDED Requirements

### Requirement: MonitorProcess is the sole owner of incident creation and initial down-alert dispatch
The system SHALL have `Uptrack.Monitoring.MonitorProcess` as the single code path that creates new incidents and dispatches initial "incident created" alerts for confirmation-threshold failures. `Uptrack.Monitoring.CheckWorker` SHALL NOT create incidents or dispatch down alerts on the DOWN branch of `handle_check_result/2`.

#### Scenario: CheckWorker DOWN path is silent
- **GIVEN** a monitor that has crossed its `confirmation_threshold` via Oban check runs
- **WHEN** `CheckWorker.handle_check_result/2` processes the failing check
- **THEN** it SHALL increment `consecutive_failures` for metrics visibility
- **AND** it SHALL NOT call `Monitoring.create_incident/1`
- **AND** it SHALL NOT call `Alerting.send_incident_alerts/2`

#### Scenario: CheckWorker UP path still resolves incidents
- **GIVEN** a monitor with an `ongoing` incident in the DB
- **WHEN** `CheckWorker.handle_check_result/2` processes an UP check
- **THEN** it SHALL call `Monitoring.resolve_all_ongoing_incidents/1`
- **AND** it SHALL dispatch resolution alerts if any incident was resolved

#### Scenario: MonitorProcess fires the down alert after consensus
- **WHEN** `MonitorProcess.maybe_trigger_alert/1` hits the `consecutive_failures >= confirmation_threshold and alerted_this_streak: false` clause on the home node
- **THEN** it creates an incident via `Monitoring.create_incident/1`
- **AND** dispatches alerts via `Uptrack.Alerting.send_incident_alerts/2`

### Requirement: MonitorProcess gates alerts on maintenance windows
The system SHALL suppress incident creation and down-alert dispatch when the monitor is under an active maintenance window, even when the consensus path is the one dispatching.

#### Scenario: Active maintenance suppresses consensus alert
- **GIVEN** a monitor is under an active maintenance window per `Maintenance.under_maintenance?/2`
- **WHEN** `MonitorProcess.maybe_trigger_alert/1` would otherwise fire an incident-created alert
- **THEN** the system SHALL NOT call `Monitoring.create_incident/1`
- **AND** SHALL NOT call `Uptrack.Alerting.send_incident_alerts/2`
- **AND** SHALL log at info level that the alert was suppressed for maintenance

### Requirement: Degradation incidents gate on maintenance windows
The system SHALL suppress creation of response-time degradation incidents and their alerts when the monitor is under an active maintenance window.

#### Scenario: Active maintenance suppresses degradation alert
- **GIVEN** a monitor is under an active maintenance window
- **AND** a check returns `response_time > response_time_threshold`
- **WHEN** `CheckWorker.check_degradation/2` evaluates the check
- **THEN** it SHALL NOT create a degradation incident
- **AND** SHALL NOT dispatch a degradation alert

### Requirement: Reminder alerts gate on maintenance windows
The system SHALL suppress "still down" reminder alerts when the monitor is under an active maintenance window.

#### Scenario: Reminder during maintenance is suppressed
- **GIVEN** an `ongoing` incident exists for a monitor under an active maintenance window
- **WHEN** `Uptrack.Alerting.IncidentReminder.maybe_send/2` evaluates whether to send the next reminder
- **THEN** it SHALL NOT dispatch the reminder
- **AND** it SHALL NOT update `last_reminder_sent_at`

### Requirement: Consensus requires majority under timeout
The system SHALL require strictly more than 50% of expected regions to have reported check results before declaring a consensus verdict when the consensus window times out. If fewer regions have reported by timeout, no state change and no alert SHALL occur for that check cycle.

#### Scenario: 3-region monitor, 2 regions report DOWN, 1 times out
- **GIVEN** a monitor with 3 expected regions and `@consensus_timeout_ms` set
- **AND** 2 regions report "down" within the timeout
- **AND** the third region does not report before timeout
- **WHEN** `Consensus.enough_results?/1` is evaluated at timeout
- **THEN** it SHALL return true (2 out of 3 is a strict majority)
- **AND** the DOWN verdict SHALL be permitted to fire

#### Scenario: 5-region monitor, 2 regions report DOWN, 3 time out
- **GIVEN** a monitor with 5 expected regions
- **AND** only 2 regions have reported within the timeout
- **WHEN** `Consensus.enough_results?/1` is evaluated at timeout
- **THEN** it SHALL return false (2 out of 5 is not a strict majority)
- **AND** NO verdict SHALL be fired
- **AND** the system SHALL log "insufficient data" at info level

#### Scenario: Single-region monitor with one result
- **GIVEN** a monitor with 1 expected region
- **AND** that region has reported within the timeout
- **WHEN** `Consensus.enough_results?/1` is evaluated
- **THEN** it SHALL return true (1 out of 1 is a strict majority)

### Requirement: Heartbeat incidents dispatch alerts
The system SHALL dispatch notification alerts for missed-heartbeat incidents created by `Uptrack.Monitoring.Heartbeat`, gated by the maintenance-window check.

#### Scenario: Missed heartbeat outside maintenance fires an alert
- **GIVEN** a heartbeat monitor has exceeded its expected interval
- **AND** the monitor is NOT under an active maintenance window
- **WHEN** `Heartbeat.create_missed_heartbeat_incident/3` successfully creates the incident
- **THEN** the system SHALL call `Alerting.send_incident_alerts/2` for that incident

#### Scenario: Missed heartbeat during maintenance is silent
- **GIVEN** a heartbeat monitor has exceeded its expected interval
- **AND** the monitor IS under an active maintenance window
- **WHEN** `Heartbeat.create_missed_heartbeat_incident/3` evaluates the check
- **THEN** the system SHALL NOT create the incident
- **AND** SHALL NOT dispatch an alert

### Requirement: Degradation incidents upgrade in place on hard DOWN
The system SHALL upgrade an `ongoing` degradation-only incident in place when a hard DOWN check subsequently fires for the same monitor, rather than leaving the degradation incident unchanged.

#### Scenario: Hard DOWN upgrades an ongoing degradation incident
- **GIVEN** an `ongoing` incident exists for a monitor whose `cause` indicates response-time degradation
- **WHEN** the monitor's consensus path determines a hard DOWN
- **THEN** the existing incident's `cause` SHALL be updated to the hard-down error message
- **AND** a new `incident_update` row SHALL be created with metadata indicating the `degraded_to_down` transition
- **AND** a single "incident updated" alert SHALL be dispatched (not a second "incident created" alert)

#### Scenario: Hard DOWN with no existing incident creates a new one
- **GIVEN** no `ongoing` incident exists for the monitor
- **WHEN** the consensus path determines a hard DOWN
- **THEN** a new incident SHALL be created with the hard-down error as its cause
- **AND** a standard "incident created" alert SHALL be dispatched

### Requirement: Escalation re-verifies incident state before paging
The system SHALL re-read the incident from the DB immediately before dispatching an escalation alert. If the incident's `status` is no longer `ongoing` or `acknowledged_at` is no longer nil, the escalation step SHALL be aborted without dispatching.

#### Scenario: Escalation fires on a still-ongoing, unacknowledged incident
- **GIVEN** an `ongoing` incident with `acknowledged_at: nil`
- **WHEN** `EscalationWorker.perform/1` reaches its dispatch step
- **THEN** the system SHALL re-read the incident
- **AND** dispatch the alert since status is still `ongoing` and acknowledgement is still nil

#### Scenario: Escalation aborts on a resolved incident
- **GIVEN** an incident whose `status` has changed to `resolved` after the escalation job was scheduled
- **WHEN** `EscalationWorker.perform/1` reaches its dispatch step
- **THEN** the system SHALL re-read the incident and observe the new status
- **AND** SHALL NOT dispatch the alert
- **AND** SHALL return `:ok` (no retry)

#### Scenario: Escalation aborts on an acknowledged incident
- **GIVEN** an `ongoing` incident whose `acknowledged_at` has been set after the escalation job was scheduled
- **WHEN** `EscalationWorker.perform/1` reaches its dispatch step
- **THEN** the system SHALL NOT dispatch the alert
- **AND** SHALL return `:ok`

### Requirement: Alert delivery retries use an idempotency token where supported
The system SHOULD attach the `notification_deliveries.id` as an idempotency token when dispatching through providers that accept one. Initial scope covers Telegram; other providers MAY be added in future changes.

#### Scenario: Telegram delivery retry uses the same delivery id
- **GIVEN** an `AlertDeliveryWorker` Oban job for a Telegram delivery that failed mid-flight and is being retried
- **WHEN** the retry attempt invokes the Telegram client
- **THEN** the client call SHALL include the `notification_deliveries.id` of the original attempt as the idempotency token
- **AND** the original and retry attempts SHALL share the same token value
