## Why

`app.monitor_checks` was the original storage tier for every check result. VictoriaMetrics has since been added as a time-series backend and already receives every check metric via `Uptrack.Metrics.Batcher`. The table has become redundant write overhead — every check hits Postgres AND VictoriaMetrics — while the table grows without bound and is queried for increasingly few things.

Three concrete problems this creates today:

1. **Table bloat.** At 30-second intervals across all monitors, the table accumulates millions of rows per day with no TTL or partition strategy. The `app.monitor_checks` table already has 348k+ rows with no archival plan.
2. **Dual writes with no consistency guarantee.** CheckWorker inserts to Postgres and the Batcher writes to VictoriaMetrics independently. If either fails, the two stores diverge silently.
3. **Regional response times broken.** Only the `check_region` of the coordinator node is stored in `monitor_checks`. VictoriaMetrics already has correct per-region labels on every metric, so the "Regional Response Times" UI only shows EU while VM has all regions.

## What Changes

- Migrate uptime percentage queries from `app.monitor_checks` to VictoriaMetrics (`avg_over_time`)
- Migrate uptime chart data queries to VictoriaMetrics
- Migrate data export daily stats to VictoriaMetrics
- Remove the `AppRepo.insert()` call from `CheckWorker` (stop writing to the table)
- Drop `app.monitor_checks` table via migration
- Remove `MonitorCheck` schema module and all related code
- Fix regional response times in the frontend (now reads from VM which has correct per-region labels)

## Capabilities

### Modified Capabilities

- `monitor-check-history`: Uptime %, response time charts, and check history all served from VictoriaMetrics instead of Postgres. Behavior unchanged from the user's perspective.
- `data-export`: Daily aggregates (`/api/export`) computed from VictoriaMetrics queries.

### Removed Capabilities

- Postgres-based fallback for check history (VM becomes the single source of truth — no silent degradation path)
- `app.monitor_checks` table (dropped permanently)

## Impact

**Database**: Drop migration for `app.monitor_checks`. Removes the largest and fastest-growing table in the `app` schema.

**Backend**:
- Remove `Uptrack.Monitoring.MonitorCheck` schema module
- Remove `Monitoring.create_monitor_check/1`, `get_recent_checks/2`, `get_latest_check/1`, `get_uptime_percentage/2`, `get_uptime_chart_data/2` from `monitoring.ex` — replace with `Metrics.Reader` equivalents
- Remove Postgres fallback branch in `MonitorController.checks/2`
- Remove MonitorCheck join from status page uptime trend query
- Update `ExportController` daily stats to use `Metrics.Reader.get_daily_uptime/3`
- Update `AnalyticsController` to use `Metrics.Reader`

**Frontend**: No API contract changes. Regional response times will correctly show all regions once per-region VM labels are surfaced in the API response.

**No downtime required.** Writes to `app.monitor_checks` stop before the table is dropped. VictoriaMetrics is already receiving all check data.
