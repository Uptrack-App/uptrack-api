## 1. Maintenance-window gates (high severity, mechanical)

- [ ] 1.1 `MonitorProcess.maybe_trigger_alert/1` (lib/uptrack/monitoring/monitor_process.ex:395): before `Monitoring.create_incident/1`, call `Maintenance.under_maintenance?(state.monitor_id, state.organization_id)` and skip both creation and alert dispatch when true (match existing CheckWorker suppression semantics). Log at info.
- [ ] 1.2 `CheckWorker.check_degradation/2` (lib/uptrack/monitoring/check_worker.ex:575-615): add the same maintenance gate before `Monitoring.create_incident/1`. Log at info on suppression.
- [ ] 1.3 Reminder maintenance gate: in `Uptrack.Alerting.IncidentReminder.maybe_send/2` (lib/uptrack/alerting/incident_reminder.ex) OR at the entry of `Alerting.send_incident_reminder/2` (lib/uptrack/alerting.ex:114-146) — whichever is invoked before channel dispatch — call `Maintenance.under_maintenance?(monitor.id, monitor.organization_id)` and return early (without updating `last_reminder_sent_at`) when true.

## 2. Single-owner incident creation (high severity, design change)

- [ ] 2.1 Remove the DOWN-path `create_incident` + `send_incident_alerts` + `notify_subscribers_incident` calls from `CheckWorker.handle_check_result/2` (lib/uptrack/monitoring/check_worker.ex:498-546). Keep the `increment_consecutive_failures` call and the `schedule_confirmation_check/1` so metrics and scheduling still work.
- [ ] 2.2 Add a moduledoc block to `Uptrack.Monitoring` (lib/uptrack/monitoring.ex) documenting the ownership boundary: `MonitorProcess` is the single writer of new incidents and dispatcher of initial down alerts; `CheckWorker` is responsible only for persistence, counter maintenance, and up-path resolution.
- [ ] 2.3 Update `Uptrack.Monitoring.CheckWorker` moduledoc to reflect its demoted responsibility.

## 3. Consensus quorum under timeout (medium severity)

- [ ] 3.1 Rewrite `Uptrack.Monitoring.Consensus.enough_results?/1` (lib/uptrack/monitoring/consensus.ex:45-48) so that on timeout the function returns true only when `map_size(results) * 2 > length(expected_regions)`. Before timeout, keep the existing "all expected regions have replied" rule.
- [ ] 3.2 Add a sibling `log_insufficient_data/1` (or inline log) in `MonitorProcess.try_consensus/1` so "insufficient data" timeouts produce a visible info-level log with the monitor_id and the responding region set.
- [ ] 3.3 Verify the degenerate cases: 1-region monitor with 1 response, 1-region monitor with 0 responses at timeout, 2-region monitor with 1 response at timeout (should now return false — was previously `>= 2`-required anyway, but confirm).

## 4. Heartbeat alert dispatch (medium severity)

- [ ] 4.1 In `Uptrack.Monitoring.Heartbeat.create_missed_heartbeat_incident/3` (lib/uptrack/monitoring/heartbeat.ex:149), after a successful `Monitoring.create_incident/1`, check `Maintenance.under_maintenance?/2` for the monitor. If not under maintenance, call `Alerting.send_incident_alerts/2` and `Alerting.notify_subscribers_incident/2` using the same pattern as `MonitorProcess`. If under maintenance, log at info and skip dispatch.
- [ ] 4.2 If the same file has a broadcast hook (e.g. `Events.broadcast_incident_created/2`), invoke it on the successful-create path too, matching the check-worker/monitor-process pattern.

## 5. Degradation → DOWN upgrade (medium severity)

- [ ] 5.1 In the DOWN branch of `MonitorProcess.maybe_trigger_alert/1`, when `Monitoring.get_ongoing_incident/1` returns an existing incident whose `cause` indicates degradation (detect via a prefix like `"Response time degradation"` — the exact string used by `check_degradation/2`), call a new `Monitoring.upgrade_incident_to_down/2` function that: (a) updates the incident's `cause` to the hard-down error message, (b) creates an `incident_updates` row with `metadata: %{transition: "degraded_to_down"}`, and (c) dispatches an "incident updated" alert rather than a second "incident created" alert.
- [ ] 5.2 Add `Monitoring.upgrade_incident_to_down/2` in lib/uptrack/monitoring.ex with the changeset/update/insert logic.
- [ ] 5.3 Wire the alerting side: add `Alerting.send_incident_update_alerts/2` that dispatches on the "incident_updated" event type, or reuse an existing function if one is available.

## 6. Escalation re-verify (medium severity)

- [ ] 6.1 In `Uptrack.Escalation.EscalationWorker.perform/1` (lib/uptrack/escalation/escalation_worker.ex:26-59), between the initial read and the alert-dispatch call, re-read the incident: `current = Monitoring.get_incident(incident.id)`. If `current.status != "ongoing"` OR `current.acknowledged_at != nil`, log at info and return `:ok` without dispatching.
- [ ] 6.2 Verify the Oban retry semantics: the early return should be treated as successful completion (no retry), which matches `:ok`.

## 7. Alert delivery idempotency (low severity, Telegram-scoped)

- [ ] 7.1 Modify `Uptrack.Alerting.AlertDeliveryWorker` (lib/uptrack/alerting/alert_delivery_worker.ex) to pass the `notification_deliveries.id` into the Telegram adapter as an idempotency token. For non-Telegram adapters, no behavior change.
- [ ] 7.2 Modify `Uptrack.Alerting.TelegramAlert` (or equivalent Telegram adapter in lib/uptrack/alerting/telegram_alert.ex) to include the token in the API request (Telegram's Bot API accepts a `disable_notification` and a deterministic message-id derivation is not native — if the provider has no direct idempotency field, use the token as a message-suffix metadata tag so dedup can happen on user inspection; verify in-code what the Telegram bot library supports).
- [ ] 7.3 If the Telegram adapter/library doesn't support any idempotency primitive, downgrade this task to "add an info log capturing the delivery id on each attempt so we can retroactively dedup observability."

## 8. Tests

- [ ] 8.1 Test: `MonitorProcess.maybe_trigger_alert/1` under active maintenance → no incident created, no alert fired.
- [ ] 8.2 Test: `CheckWorker.check_degradation/2` under active maintenance → no degradation incident.
- [ ] 8.3 Test: `IncidentReminder.maybe_send/2` under active maintenance → no reminder dispatched, `last_reminder_sent_at` unchanged.
- [ ] 8.4 Test: `CheckWorker.handle_check_result/2` DOWN branch does not call `Monitoring.create_incident/1` (stub/mox the function and assert not-called).
- [ ] 8.5 Test: `Consensus.enough_results?/1` with `{expected: 3 regions, results: 2, timeout: true}` returns true; with `{expected: 5 regions, results: 2, timeout: true}` returns false.
- [ ] 8.6 Test: `Heartbeat.create_missed_heartbeat_incident/3` dispatches alerts; under maintenance it does not.
- [ ] 8.7 Test: degradation → DOWN upgrade: seed an ongoing degradation incident, invoke the DOWN path, assert the original incident's `cause` was updated and an `incident_updates` row was inserted with `transition: "degraded_to_down"`.
- [ ] 8.8 Test: `EscalationWorker.perform/1` with an already-resolved incident → no dispatch, returns `:ok`.
- [ ] 8.9 `mix test` locally — all green (existing unrelated failures in the suite from pre-existing test drift are acceptable; new tests must pass).

## 9. Deploy (sequential)

- [ ] 9.1 `git add` all modified files (flake-dirty-tree includes only tracked files).
- [ ] 9.2 `cd uptrack-api && nix run github:zhaofengli/colmena -- apply --on nbg1`.
- [ ] 9.3 Verify nbg1: `systemctl is-active uptrack`, tail logs for "Confirmed DOWN" lines — should now come only from `MonitorProcess`, not `CheckWorker`. Verify no alerts during any active maintenance window.
- [ ] 9.4 `nix run github:zhaofengli/colmena -- apply --on nbg2`.
- [ ] 9.5 Verify nbg2 with the same checks.

## 10. Post-deploy validation

- [ ] 10.1 Spot-check: query `app.incidents` for any fresh rows created during the deploy window and confirm each has exactly one `notification_deliveries` row per configured channel (no duplicates from the removed CheckWorker path).
- [ ] 10.2 Spot-check: run a synthetic maintenance window on a test monitor (start window → trigger failure → end window) and confirm no alert fires during the window.
- [ ] 10.3 Archive both this change and `fix-stale-incident-renotifications` via `openspec archive` once the system has been running clean for 24h.
