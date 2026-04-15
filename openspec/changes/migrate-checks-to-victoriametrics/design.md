## Context

VictoriaMetrics is already receiving every check metric via `Uptrack.Metrics.Batcher` → `Uptrack.Metrics.Writer`. The writer posts in Prometheus line format to vminsert; `Uptrack.Metrics.Reader` queries via vmselect. The following metrics are already stored:

| Metric | Labels |
|--------|--------|
| `uptrack_monitor_status` | monitor_id, org_id, name, region |
| `uptrack_monitor_response_time_ms` | monitor_id, org_id, region |
| `uptrack_monitor_http_status` | monitor_id, org_id, region |

`region` label already exists on all metrics — fixing Regional Response Times is a side-effect of this migration with no extra work.

Current Postgres reads that need VM equivalents:

| Function | SQL Pattern | VM Equivalent |
|----------|-------------|---------------|
| `get_uptime_percentage/2` | `AVG(CASE WHEN status='up' THEN 1 ELSE 0 END)` | `avg_over_time(uptrack_monitor_status[Nd])` |
| `get_uptime_chart_data/2` | Daily GROUP BY with status counts | `avg_over_time(...)[Nd:1d]` |
| `get_recent_checks/2` | `ORDER BY checked_at DESC LIMIT 50` | Already in `Metrics.Reader.get_recent_checks/2` |
| `get_latest_check/1` | `ORDER BY checked_at DESC LIMIT 1` | Already in `Metrics.Reader.get_latest_check/1` |
| Export daily stats | Daily aggregates per monitor | `avg_over_time` + `max_over_time` per 1d step |

## Goals / Non-Goals

**Goals:**
- VictoriaMetrics as single source of truth for check data
- Correct multi-region response times in the UI
- Remove unbounded table growth from Postgres
- Eliminate dual-write inconsistency

**Non-Goals:**
- Long-term check data archival beyond VM retention (configure VM retention separately)
- Changing the check execution architecture (CheckWorker, MonitorProcess, Batcher unchanged except removing the Postgres insert)
- Migrating historical data from Postgres to VM (VM already has its own history; Postgres history is dropped with the table)

## Decisions

### 1. Stop writes first, drop table after a safe window

**Decision**: Ship in two deploys. Deploy 1: remove the `AppRepo.insert()` from CheckWorker. Deploy 2 (one week later): drop the table.

**Why**: If VM has an outage or bug after Deploy 1, we can verify the impact against the still-present Postgres data. The one-week gap gives confidence before the destructive step. The table is not queried after Deploy 1 so it's just wasted disk — acceptable for one week.

**Alternative rejected**: Drop table in same deploy. Risky if VM queries have bugs; no rollback path for data.

---

### 2. VM becomes the single source of truth — no Postgres fallback

**Decision**: Remove the fallback branch in `MonitorController.checks/2` that falls back to `Monitoring.get_recent_checks/2` when VM returns empty.

**Why**: The fallback creates a false safety net that masks VM connectivity problems. If VM is unreachable, the right behavior is to surface an error so it gets fixed — not silently serve stale Postgres data that diverges from what VM has. A proper VM health check in `/api/health` is the correct reliability mechanism.

**Tradeoff**: If VM goes down, check history returns an error. Mitigation: VM is already in the health check endpoint. Alert on it.

---

### 3. Uptime % via `avg_over_time` — same semantics as the SQL `AVG`

**Decision**: Use `avg_over_time(uptrack_monitor_status{monitor_id="..."}[Nd])` where N is the number of days.

**Why it's equivalent**: `uptrack_monitor_status` is a gauge written as `1` (up) or `0` (down) at every check interval. `avg_over_time` over N days gives the fraction of intervals that were `1`, which is identical to the SQL `AVG(CASE WHEN status='up' THEN 1 ELSE 0 END)`. The result is a float 0.0–1.0, multiply by 100 for percentage.

**Caveat**: VM uses the actual sample timestamps so gaps (monitor paused, node restart) are handled correctly — paused intervals are simply absent, VM won't count them as downtime. The SQL query has the same behavior (no row = not counted).

---

### 4. Daily uptime chart via subquery range with 1d step

**Decision**: Use `query_range` with `step=1d` and `avg_over_time(...[1d])`.

**PromQL**:
```
avg_over_time(uptrack_monitor_status{monitor_id="UUID"}[1d])
```
with `start=<N days ago>`, `end=<now>`, `step=1d`.

Each data point is the average status for that calendar day. This matches the existing SQL GROUP BY date behavior.

**For export**, also query `max_over_time(uptrack_monitor_response_time_ms[1d])` for p-max and `quantile_over_time(0.95, uptrack_monitor_response_time_ms[1d])` for p95 per day.

---

### 5. Regional response times — surface per-region data from VM

**Decision**: The VM `region` label on `uptrack_monitor_response_time_ms` already contains the worker node's region. Surface this in the `GET /api/monitors/:id` response as `region_results` map.

**New VM query** in `Metrics.Reader`:
```
uptrack_monitor_response_time_ms{monitor_id="UUID"}
```
Returns one result per region label. Map `{region: "europe", value: 74}` → existing `region_results` shape in the API response. This fixes the UI without any frontend changes.

---

### 6. Export format unchanged

**Decision**: The CSV/JSON export output format stays identical. Only the query source changes from Postgres → VM.

**Columns preserved**: date, total_checks, up_checks, avg_response_time_ms, p95_response_time_ms, p99_response_time_ms.

**Implementation**: `Metrics.Reader.get_daily_uptime/3` already returns `avg_rt`. Add p95/p99 via `quantile_over_time`. `total_checks` is derived from `count_over_time(uptrack_monitor_status[1d])`.

## Migration Sequence

```
Deploy 1
  └── Remove AppRepo.insert() from CheckWorker
  └── All queries now read from VM (Postgres table still exists but no new writes)

Wait 1 week (monitor for issues)

Deploy 2
  └── Drop app.monitor_checks table
  └── Remove MonitorCheck schema module
  └── Remove all dead Monitoring context functions
```

## Files Changed

| File | Change |
|------|--------|
| `lib/uptrack/monitoring/check_worker.ex` | Remove `Monitoring.create_monitor_check/1` call |
| `lib/uptrack/monitoring.ex` | Remove `create_monitor_check/1`, `get_recent_checks/2`, `get_latest_check/1`, `get_uptime_percentage/2`, `get_uptime_chart_data/2`, MonitorCheck join in status uptime query |
| `lib/uptrack/metrics/reader.ex` | Add `get_uptime_percentage/2`, `get_uptime_chart_data/2`, `get_daily_stats/3`, `get_region_response_times/1` |
| `lib/uptrack_web/controllers/api/monitor_controller.ex` | Remove Postgres fallback in `checks/2`, add region data to `show/2` |
| `lib/uptrack_web/controllers/api/analytics_controller.ex` | Switch uptime_chart_data source to VM |
| `lib/uptrack_web/controllers/api/export_controller.ex` | Switch daily stats to VM |
| `lib/uptrack/monitoring/monitor_check.ex` | Delete entire file (Deploy 2) |
| `priv/app_repo/migrations/YYYYMMDD_drop_monitor_checks.exs` | Drop table (Deploy 2) |
