## Why

To scale Uptrack to 100k–1M+ monitors while delivering 2-year forensic retention on Pro plans, the storage architecture for DOWN-check details must stop accumulating in Postgres. The current `monitor_check_failures` table is single-node and unbounded: at 1 M monitors / 2 y retention, Postgres alone would consume ~300 GB/node on disk-constrained nbg3/nbg4 (500 GB each). Competitor research (Checkly, Better Stack, Datadog, New Relic, Site24x7) confirms the industry splits forensic-detail from numeric-aggregate storage: rich detail in a log store, aggregates in a metrics store, only thin incident metadata in OLTP. Uptrack already deploys VictoriaMetrics for metrics; adding VictoriaLogs for log-shaped forensic events completes the picture at ~15× better storage efficiency than Postgres JSONB.

## What Changes

- **Deploy VictoriaLogs** single-node on nbg3 and nbg4 with 2-year global retention (`-retentionPeriod=2y`), mirroring the existing VM dual-write topology. Stream field = `monitor_id` only (cardinality-safe).
- **Deploy vlagent** on nbg1 and nbg2 (app nodes). App code writes once to localhost vlagent, which handles dual-write + on-disk buffering + retry.
- **New Elixir context `Uptrack.Failures`** defines the forensic-event contract as a `@behaviour`. Two implementations: `Uptrack.Failures.PostgresAdapter` (legacy, writes to existing `monitor_check_failures` table) and `Uptrack.Failures.VictoriaLogsAdapter` (new). Selected via config; supports parallel dual-write during cutover.
- **Sharded Batcher with per-shard persistent Gun connections** (`Uptrack.Failures.Batcher` supervisor + `Uptrack.Failures.Batcher.Shard` GenServers). N shards (default `System.schedulers_online()`), each owning one long-lived Gun connection to `localhost:9429`. **No connection pool** — pool-size ceilings are incompatible with the throughput target. Writes are routed by `:erlang.phash2(monitor_id, shard_count)`. Flush on first of: 1 s interval / 1000 lines / 1 MB body. On buffer overflow, drop-oldest.
- **Dedup/sampling in `MonitorProcess`**: per-monitor fingerprint `(status_code, error_class, body_sha256)` lives in the GenServer state. `Uptrack.Failures.record/1` is called only on: first DOWN of a streak, fingerprint change, incident lifecycle event (created / upgraded / resolved), and state transitions (UP → DOWN and DOWN → UP). Not every DOWN check.
- **Add `incidents.vl_trace_id` column** (uuid, generated at incident create). Points into VL so the incident detail view can fetch full forensic from VL on demand.
- **Add VictoriaMetrics counter + histogram**: `uptrack_check_failures_total{monitor_id, status_code, region}` and `uptrack_check_duration_ms_bucket{monitor_id, status, region}`. Emitted via the existing vmagent path — no new metrics pipeline.
- **Incident detail API reads from VL** via `vl_trace_id`, falls back to "forensic unavailable" when VL data is missing (older incidents, VL downtime, post-retention).
- **Deprecate `monitor_check_failures` table** — keep populated via the Postgres adapter for a transitional period (default: off after this change ships), drop table in a follow-up change once VL read path is validated in production.
- **BREAKING** (internal only): `MonitorProcess.record_result/1` no longer calls `Uptrack.Monitoring.CheckFailures.record/1` directly. Call is routed through the `Uptrack.Failures` behaviour.

## Capabilities

### New Capabilities
- `failure-forensics-storage`: Defines how DOWN-check detail events are captured, stored, queried, and retained across the VM / VL / Postgres split.

### Modified Capabilities
<!-- none — the existing incident-lifecycle capability is unaffected -->

## Impact

- **Code**: new `lib/uptrack/failures.ex` + `lib/uptrack/failures/*.ex` adapters. Touches `lib/uptrack/monitoring/monitor_process.ex` (dedup state, call site). Touches `lib/uptrack_web/controllers/api/incident_controller.ex` (read path). New `lib/uptrack/failures/vl_client.ex` for HTTP ingest + query.
- **Migration**: add `vl_trace_id uuid` to `app.incidents`. No data change.
- **Infra (NixOS)**: new `infra/nixos/modules/services/victorialogs.nix` (on nbg3, nbg4) and `infra/nixos/modules/services/vlagent.nix` (on nbg1, nbg2). Agenix secrets if auth is enabled (initial: Tailscale-only bind, no auth).
- **Deploy**: sequential — nbg3 (install VL) → nbg4 (install VL) → nbg1 (vlagent + Elixir) → nbg2 (vlagent + Elixir). VM pipeline unchanged.
- **External surface**: `GET /api/incidents/:id/forensic` new endpoint returning VL payload. No breaking changes to existing `GET /api/incidents/:id`.
- **Runtime dependency**: Elixir app now has a soft dependency on vlagent reachability on localhost. Writes are fire-and-forget; if vlagent is down, forensic events are dropped (logged at warn). Incident creation succeeds regardless.
- **User-visible behavior change**: `GET /api/monitor/:id/failures` (the dashboard "recent failures" view backed by `CheckFailures.recent_for_monitor/2`) will show fingerprint-grouped rows instead of every DOWN check. For a monitor failing 50 times with identical `{status_code, error_class, body_sha256}`, users see 1 row per distinct fingerprint instead of 50. Matches Sentry/Rollbar-style grouping; reduces noise without losing information (sample body and count are preserved). Call out in release notes.
