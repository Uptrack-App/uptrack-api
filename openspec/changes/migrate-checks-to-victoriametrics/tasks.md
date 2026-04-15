## Deploy 1 — Stop writes, migrate reads to VM

- [ ] **Add `get_uptime_percentage/2` to `Metrics.Reader`**
  Using `avg_over_time(uptrack_monitor_status{monitor_id="..."}[Nd])`. Returns float 0.0–1.0.

- [ ] **Add `get_uptime_chart_data/2` to `Metrics.Reader`**
  `query_range` with step=1d, returns `[{date, uptime_pct, avg_response_time_ms}]`.

- [ ] **Add `get_daily_stats/3` to `Metrics.Reader`**
  Per-day: total_checks (`count_over_time`), up_checks, avg/p95/p99 response time. For export.

- [ ] **Add `get_region_response_times/1` to `Metrics.Reader`**
  Query latest `uptrack_monitor_response_time_ms` grouped by `region` label. Returns `%{"europe" => 74, "us" => 120, ...}`.

- [ ] **Update `AnalyticsController`** to call `Metrics.Reader.get_uptime_chart_data/2` instead of `Monitoring.get_uptime_chart_data/2`.

- [ ] **Update `ExportController`** daily stats to call `Metrics.Reader.get_daily_stats/3`.

- [ ] **Update `MonitorController.checks/2`** — remove Postgres fallback branch, return error if VM unavailable.

- [ ] **Update `MonitorController.show/2`** — include `region_results` from `Metrics.Reader.get_region_response_times/1` in the response.

- [ ] **Remove `AppRepo.insert()` from `CheckWorker`** — stop writing to `app.monitor_checks`.

- [ ] **Remove dead functions from `monitoring.ex`**: `create_monitor_check/1`, `get_recent_checks/2`, `get_latest_check/1` (superseded by cache/VM), `get_uptime_percentage/2`, `get_uptime_chart_data/2`.

- [ ] **Deploy and verify** — confirm uptime %, charts, export, and regional response times all work correctly.

---

## Deploy 2 — Drop table (1 week after Deploy 1)

- [ ] **Create drop migration** `priv/app_repo/migrations/YYYYMMDD_drop_monitor_checks.exs`

- [ ] **Delete `lib/uptrack/monitoring/monitor_check.ex`**

- [ ] **Remove `has_many :monitor_checks` from `Monitor` schema** (if present)

- [ ] **Deploy and verify** — confirm no references to dropped table remain.
