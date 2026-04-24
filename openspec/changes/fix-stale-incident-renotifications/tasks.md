## 1. Code changes

- [x] 1.1 Change `Uptrack.Monitoring.create_incident/1` (lib/uptrack/monitoring.ex): on `ongoing_unique_conflict?/1`, return `{:error, :already_ongoing}` instead of `{:ok, existing}`. Remove the now-unused `get_ongoing_incident` lookup inside the error branch.
- [x] 1.2 Update `Uptrack.Monitoring.CheckWorker.handle_check_result/2` (lib/uptrack/monitoring/check_worker.ex ~line 517): add an `{:error, :already_ongoing}` match clause that logs at info level and returns without broadcasting or alerting. Keep the existing `{:error, changeset}` branch for real validation failures.
- [x] 1.3 Update `Uptrack.Monitoring.MonitorProcess.maybe_trigger_alert/1` (lib/uptrack/monitoring/monitor_process.ex ~line 384): add an `{:error, :already_ongoing}` match clause in the Task.Supervisor child — log at info and return without broadcasting or alerting.
- [x] 1.4 Extend `Uptrack.Monitoring.MonitorProcess.init/1` (lib/uptrack/monitoring/monitor_process.ex:79-103) to call `Monitoring.get_ongoing_incident(monitor.id)` and hydrate `alerted_this_streak`, `incident_id`, and `consecutive_failures` from the result per the `incident-lifecycle` spec.

## 2. Tests

- [x] 2.1 Add a test for `Monitoring.create_incident/1` that inserts an ongoing incident, calls `create_incident` again for the same monitor, and asserts `{:error, :already_ongoing}`.
- [x] 2.2 Add a test for `MonitorProcess.init/1` that inserts an ongoing incident, starts the process, and asserts the state has `alerted_this_streak: true`, `incident_id` matching the row, `consecutive_failures == confirmation_threshold`.
- [x] 2.3 Run `mix test` locally — all green.

## 3. Deploy (sequential)

- [ ] 3.1 `git add` all modified files so the flake source includes them (dirty-tree flakes exclude untracked files).
- [ ] 3.2 `cd uptrack-api && nix run github:zhaofengli/colmena -- apply --on nbg1`.
- [ ] 3.3 Verify nbg1: `ssh nbg1 "systemctl is-active uptrack && journalctl -u uptrack -n 50 --no-pager"`. Confirm no crash loops and no unexpected "incident_created" log spam.
- [ ] 3.4 `nix run github:zhaofengli/colmena -- apply --on nbg2`.
- [ ] 3.5 Verify nbg2 with the same health checks as 3.3.

## 4. Post-deploy data cleanup

- [ ] 4.1 After BOTH nodes are on the new code, run the cleanup SQL on the DB primary: `UPDATE app.incidents SET status='resolved', resolved_at=NOW(), duration=GREATEST(0, EXTRACT(EPOCH FROM (NOW()-started_at))::int), updated_at=NOW() WHERE status='ongoing' AND monitor_id IN (SELECT id FROM app.monitors WHERE consecutive_failures = 0);`
- [ ] 4.2 Verify the stale-ongoing count is 0: `SELECT COUNT(*) FROM app.incidents i JOIN app.monitors m ON m.id=i.monitor_id WHERE i.status='ongoing' AND m.consecutive_failures = 0;`
- [ ] 4.3 Spot-check: confirm no fresh "MONITOR DOWN" Telegram alerts fired for incidents with old `started_at` timestamps during deploy window.
