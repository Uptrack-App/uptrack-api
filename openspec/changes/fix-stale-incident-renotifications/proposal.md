## Why

Users receive "MONITOR DOWN" Telegram/email alerts for incidents that started days ago, re-fired every time the Phoenix app restarts (e.g. during deploys). Production currently has 23 stale `ongoing` incidents that re-notify on every deploy, eroding alert trust and burning customer attention. The root cause is a divergence between in-memory `MonitorProcess` state and the DB on restart, compounded by `create_incident` returning `{:ok, existing}` on unique-index conflict so callers can't tell a fresh incident from a stale one.

## What Changes

- `Uptrack.Monitoring.create_incident/1` returns `{:error, :already_ongoing}` instead of `{:ok, existing}` when the `incidents_one_ongoing_per_monitor_idx` unique constraint is hit. **BREAKING** for internal callers — `check_worker.ex` and `monitor_process.ex` must match the new clause and suppress broadcast/alerting on that branch.
- `Uptrack.Monitoring.MonitorProcess.init/1` hydrates its state from the DB. If `get_ongoing_incident/1` returns a row at startup, the process initializes with `alerted_this_streak: true`, `incident_id: existing.id`, `consecutive_failures: confirmation_threshold`. This routes the next successful check through the resolve clause at line 250 instead of the no-op clause at line 277.
- One-off data cleanup resolves the 23 currently-stale `ongoing` incidents (monitors already show `consecutive_failures = 0`, so they've recovered). Runs after deploy as a SQL UPDATE, not a migration.

## Capabilities

### New Capabilities
- `incident-lifecycle`: Covers when incidents are created, prevented from duplication, and resolved, including the contract between `MonitorProcess` in-memory state and the `incidents` table across process restarts.

### Modified Capabilities
<!-- none — no existing incident-related spec to amend -->

## Impact

- **Code**: `lib/uptrack/monitoring.ex` (`create_incident/1` return contract), `lib/uptrack/monitoring/monitor_process.ex` (`init/1` hydration + alert dispatch on `:already_ongoing`), `lib/uptrack/monitoring/check_worker.ex` (alert dispatch on `:already_ongoing`).
- **Data**: One-off SQL UPDATE resolving ~23 stale `ongoing` incidents. No schema change; `incidents_one_ongoing_per_monitor_idx` unique index already exists (migration `20260420100000`).
- **Deploy**: Sequential Colmena apply — `nbg1` first, verify, then `nbg2`. Migrations auto-run via `Uptrack.Release.migrate()` but this change adds no migration.
- **No API / FE surface changes.** Notification payload and cadence for genuinely new incidents is unchanged.
