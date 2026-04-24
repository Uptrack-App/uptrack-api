## Why

A monitoring/alerting audit surfaced 10 remaining false-alert gaps after the previous `fix-stale-incident-renotifications` change. Left unfixed, customers will continue to receive alerts during maintenance windows (from three separate paths that forgot the gate), duplicate alerts from racing code paths, heartbeat incidents with no notification, minority-region false "DOWN" verdicts, and escalation pages for incidents that were already acknowledged. These are high-trust failures — users turn off notifications or churn when alerts stop being trustworthy.

## What Changes

- **H1. MonitorProcess respects maintenance windows.** `maybe_trigger_alert/1` (lib/uptrack/monitoring/monitor_process.ex:395) gates incident creation and alert dispatch on `Maintenance.under_maintenance?/2`, matching `CheckWorker`'s existing behavior.
- **H2. Degradation alerts respect maintenance windows.** `CheckWorker.check_degradation/2` (lib/uptrack/monitoring/check_worker.ex:575-615) applies the same maintenance gate before creating degradation incidents.
- **H3. Single-owner incident creation.** **BREAKING** for internal flow: `MonitorProcess` becomes the sole creator of incidents and dispatcher of down alerts. `CheckWorker.handle_check_result/2` keeps its UP-path responsibilities (persist check, reset counter, resolve ongoing incidents) but stops calling `create_incident` / `send_incident_alerts` on DOWN. Ownership is documented in `monitoring.ex` moduledoc.
- **M1. Reminder alerts respect maintenance windows.** `IncidentReminder.maybe_send/2` and/or `Alerting.send_incident_reminder/2` call `Maintenance.under_maintenance?/2` before dispatch.
- **M2. Consensus requires majority under timeout.** `Consensus.enough_results?/1` (lib/uptrack/monitoring/consensus.ex:45-48) requires `>50%` of expected regions to have reported before a timeout-based verdict can fire. If fewer regions respond within the window, treat as "insufficient data" — no state change, no alert.
- **M3. Heartbeat incidents dispatch alerts.** `Heartbeat.create_missed_heartbeat_incident/3` (lib/uptrack/monitoring/heartbeat.ex:149) calls `Alerting.send_incident_alerts/2` after a successful create, gated by the maintenance check.
- **M4. Degradation → DOWN upgrade in place.** When a hard DOWN occurs on a monitor that already has an `ongoing` degradation-only incident, update the existing incident's `cause` to reflect the hard failure instead of silently no-op'ing. No schema change.
- **M5. Escalation re-verifies before paging.** `EscalationWorker.perform/1` (lib/uptrack/escalation/escalation_worker.ex:26-59) re-reads the incident immediately before dispatching alerts; aborts if `status` has changed or `acknowledged_at` is now set.
- **L1. Alert delivery idempotency.** `AlertDeliveryWorker` passes the `notification_deliveries.id` as an idempotency token where the provider supports one. Lowest-priority item; scoped to Telegram and email.

## Capabilities

### New Capabilities
<!-- none — all findings attach to the existing incident-lifecycle capability -->

### Modified Capabilities
- `incident-lifecycle`: adds requirements for maintenance gating on every alert-emitting path, single-owner incident creation (MonitorProcess), consensus quorum under timeout, heartbeat-path alert dispatch, degradation-to-DOWN upgrade-in-place, escalation re-verification, and delivery idempotency.

## Impact

- **Code**: `lib/uptrack/monitoring.ex` (moduledoc), `lib/uptrack/monitoring/monitor_process.ex` (maintenance gate), `lib/uptrack/monitoring/check_worker.ex` (remove down-path create, add degradation maintenance gate), `lib/uptrack/monitoring/consensus.ex` (quorum), `lib/uptrack/monitoring/heartbeat.ex` (alert dispatch + maintenance gate), `lib/uptrack/alerting/incident_reminder.ex` and/or `lib/uptrack/alerting.ex` (reminder maintenance gate), `lib/uptrack/escalation/escalation_worker.ex` (re-verify), `lib/uptrack/alerting/alert_delivery_worker.ex` (idempotency token).
- **Data**: None. No schema or migration changes.
- **Tests**: New tests covering each maintenance-gate path, consensus quorum behavior, degradation upgrade, escalation re-verification, and single-owner dispatch (CheckWorker DOWN path silent).
- **Deploy**: Sequential Colmena apply — `nbg1` first, verify, then `nbg2`. No migration to run.
- **External surface**: No API or FE changes. Customer-visible effect is **fewer** alerts (correctly suppressed ones), **no** behavior change for legitimate incidents.
