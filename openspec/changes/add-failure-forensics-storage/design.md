## Context

Current state: every DOWN check writes a row to Postgres `app.monitor_check_failures` via `Uptrack.Monitoring.CheckFailures.record/1`. The table is not Citus-sharded, has 30-day retention via an Oban cleanup cron, and is currently at 0 rows / 24 KB. Existing metrics flow through vmagent on nbg1/nbg2 to VictoriaMetrics on nbg3/nbg4.

Competitor research (see `openspec/changes/add-failure-forensics-storage/research.md` if kept, otherwise previous conversation) established that the industry standard is a three-tier split: metrics in a TSDB (2 y, downsampled), forensic events in a log store (variable retention, heavily deduped), thin metadata in OLTP (full retention). Uptrack already has tiers 1 and 3; this change adds tier 2.

Key constraint: **VictoriaLogs does not support per-stream retention** (verified against VL docs, GitHub issues #302 / #6709). Only one global `-retentionPeriod` flag. This forces a single VL retention tier and a dedup discipline that keeps volume low enough for 2-year storage.

## Goals / Non-Goals

**Goals:**
- DOWN-check forensic events captured in a store that scales to 1 M+ monitors without Postgres disk growth being the bottleneck.
- 2-year forensic retention at Pro-plan scale fits comfortably in 500 GB per node.
- Pluggable backend via Elixir `@behaviour` — Postgres (legacy) and VL adapters coexist during transition, selected per environment.
- Per-monitor fingerprint dedup keeps VL write volume at ~10–100 events/sec at 1 M monitors, even during widespread incidents.
- MonitorProcess GenServer supervises its own dedup state — no central map, no hot-spot.
- vlagent on app nodes mirrors the existing vmagent pattern: fire-and-forget writes, on-disk buffer, dual-write to nbg3/nbg4.

**Non-Goals:**
- Replacing the metrics pipeline (VictoriaMetrics stays).
- Citus-sharding `incidents` or `monitor_check_failures` (separate follow-up).
- Cold tier to R2/S3 (VL doesn't support this; out of scope).
- GDPR/PII redaction patterns for response bodies (separate follow-up; initial redact-list covers auth headers only).
- Rewriting `MonitorProcess` or consensus logic beyond wiring in dedup state.
- A VL query builder for end-users; incident detail fetches a single trace_id, nothing richer.

## Decisions

### D1. Use a `@behaviour` for the failure writer, not a concrete module

```elixir
defmodule Uptrack.Failures do
  @callback record(event :: Failures.Event.t()) :: :ok | {:error, term()}
end
```

Concrete modules `Uptrack.Failures.PostgresAdapter` and `Uptrack.Failures.VictoriaLogsAdapter` implement the behaviour. The module to call is resolved at runtime via `Application.get_env(:uptrack, :failures_adapter, PostgresAdapter)`.

*Why:* Standard Elixir pattern for swappable backends (matches `Phoenix.Adapter`, `Oban.Queue`, etc.). Lets us dual-write during transition by wrapping both adapters in a `Uptrack.Failures.DualAdapter`. Enables testing with a `NoopAdapter` in the test env.

*Alternative:* Dispatch via Elixir `dispatch/1` protocol or direct function calls. Rejected — behaviours are more idiomatic, discoverable, and testable.

### D2. Dedup state lives in `MonitorProcess` GenServer, not in the Failures writer

Each `MonitorProcess` holds its own last-fingerprint tuple in GenServer state:

```elixir
defstruct [
  ...,
  last_failure_fingerprint: nil,  # {status_code, error_class, body_sha256}
  last_failure_recorded_at: nil   # DateTime, for 10-min ceiling
]
```

On every DOWN check, the process computes the fingerprint. If it matches `last_failure_fingerprint` AND `last_failure_recorded_at` is within 10 minutes, skip the write. Otherwise write + update state.

*Why:* State is naturally sharded across processes (1 M monitors = 1 M GenServers). Central dedup map would be a single point of memory pressure (~100 MB at 1 M). Per-process state is the Elixir idiom. The `last_failure_recorded_at` floor prevents long-term fingerprint collisions from suppressing writes forever.

*Alternative:* Central `:ets` table keyed by monitor_id. Rejected — reinvents what GenServer state already gives us, and adds ETS contention at 1 M+ processes.

### D3. App-side dual-write (no vlagent sidecar for initial rollout)

The Elixir app's Batcher shards write directly to both VL nodes (nbg3:9428 and nbg4:9428). No vlagent sidecar. Rationale lives in §D3.1.

*Future:* if `uptrack_forensic_events_dropped_total` shows sustained drops during VL-outage windows, revisit by flake-overriding a newer VL release that ships vlagent, and restoring vlagent's on-disk queue as the durability primary.

### D3.1. Sharded Batcher with per-shard persistent Gun connections (no pool, direct dual-write)

`Uptrack.Failures.VictoriaLogsAdapter.record/1` does NOT make an HTTP call per event. Events are routed into N batcher shards, each owning **two** dedicated long-lived Gun connections — one to each VL node (nbg3:9428 and nbg4:9428). The app does dual-write directly; no vlagent sidecar.

**Why no vlagent:** the nixpkgs `victorialogs` package at 1.35.0 does not ship a `vlagent` binary (added upstream in 1.50.0, still catching up to nixpkgs). Adding vlagent would require flake-override to a newer VL release — operational cost without material benefit at current scale. Direct dual-write in the app is one less service to deploy, monitor, and back up.

**Trade-off accepted:** we lose vlagent's local on-disk queue. If both nbg3 and nbg4 are down simultaneously, events are dropped at the shard's in-memory buffer (max 5 MB/shard) before Gun reconnects. For soft-durability forensics paired with the Postgres DualAdapter during rollout, this is acceptable. Post-cutover, watch `uptrack_forensic_events_dropped_total` closely; if it trends upward, revisit vlagent via flake override.

Routing: `shard = :erlang.phash2(monitor_id, shard_count)` → `GenServer.cast(:"Uptrack.Failures.Batcher.Shard.#{shard}", {:write, event})`.

Per shard:
- Own mailbox, own buffer (iodata list + line count + byte count).
- Own Gun connection (`:gun.open/3`, HTTP/1.1 or HTTP/2 if vlagent supports it).
- Flush on first of: **1 s interval**, **1000 lines**, **1 MB body**.
- On connection down (`:gun_down`), Gun reconnects automatically; pending events stay buffered during the blip.
- On buffer overflow (>5000 queued lines OR >5 MB bytes), **drop-oldest** with a counter metric.
- Writes via `:gun.post/4` return a `stream_ref` immediately (async); response arrives as a message and acks the batch.

*Why "no pool":* Pool-based HTTP clients (Req/Finch, Hackney) cap throughput at pool size. A pool of 50 across the whole app competes with alert traffic, monitor-check traffic, and anything else the app does. Throughput ceiling = 50 × request-rate-per-connection ≈ 5–10 k req/sec at best — hit by a single burst on a single channel.

With one persistent connection per shard, throughput ceiling becomes **bandwidth × shard_count**. On localhost loopback, each shard handles multi-GB/s in principle; we'll see 15 MB/sec aggregate at 10 k events/sec, which is 0.4% of one shard's capacity. Adding shards adds connections, adds bandwidth. Linear scale.

*Why Gun over Mint:* Gun's per-process persistent-connection model + built-in reconnect + HTTP/2 multiplexing + already-in-codebase means fewer net lines of code. Mint would require manual reconnect, manual keepalive, and hand-rolled multiplexing. Both are non-pool; Gun is less work.

*Alternative considered: Finch with size=1000.* Rejected — still a pool, still has a ceiling, and allocates connections lazily (slow on first burst). Gun's persistent model is strictly better for this workload.

*Shard count:* Default `System.schedulers_online()` (adaptive to node CPU count). Override via `config :uptrack, :failures_shard_count`. Typical: 4 on nbg1 (4 vCPU), 8 on a future bigger box.

*Overflow discipline:* **drop-oldest**. A monitor that's been down for 5 minutes has 300 events queued; if we're dropping, the freshest evidence is more debuggable than the stalest. Drop-newest was considered; it preserves incident-opening events but loses recent error-pattern changes. We chose drop-oldest because the incident row itself carries the opening payload durably (Postgres), so VL's job is to be the richest-possible *recent* history, not the authoritative log.

### D3.2. vlagent operational quirks (verified against docs)

Three facts about `vlagent` that the design must accommodate (source: https://docs.victoriametrics.com/victorialogs/vlagent/ as of v1.50.0 / 2026-04-14):

1. **HTTP/1.1 only on `/insert/jsonline`.** No HTTP/2, no h2c. Gun runs HTTP/1.1 with keep-alive. Multiplexing is not an option; we scale via more shards, not more streams per connection.
2. **Idle timeout 60 s by default** (`-http.idleConnTimeout`). A shard's Gun connection idle for > 60 s will be torn down server-side. Mitigation: **bump `-http.idleConnTimeout=10m` in the NixOS vlagent module.** Simpler than app-side heartbeats and keeps Gun pids stable.
3. **Silent drop on disk overflow.** vlagent's persistent queue (`-remoteWrite.tmpDataPath` with cap `-remoteWrite.maxDiskUsagePerURL`) evicts oldest on overflow. Insert callers get 200 OK regardless. This means **200 from vlagent = buffered, not ack'd by VL.** Durability depends on the disk queue staying below cap. Mandatory alerts on `vlagent_remotewrite_pending_data_bytes` and `vlagent_remotewrite_queue_blocked`.

Sizing: at worst-case 100 k events/sec × 1.85 KB = 185 MB/sec ingress. `-remoteWrite.maxDiskUsagePerURL=10GiB` gives ~55 s of buffer during a VL outage before drops start — tolerable for app-node crash windows; longer VL outages need operator response anyway.

### D4. Fire-and-forget writes; never block the check pipeline

`Uptrack.Failures.record/1` returns immediately after enqueueing to a `Task.Supervisor` child. If the write fails, log at warn and drop. Forensic loss during vlagent outages is preferable to blocking the check cycle.

*Why:* Check cycles are SLO-critical. Forensic telemetry is nice-to-have. This matches the existing `CheckFailures.record/1` contract (which already swallows errors).

*Alternative:* Synchronous write with bounded retry. Rejected — any slowness in vlagent would cascade to monitor check latency.

### D5. Schema: one VL stream per monitor_id

Stream fields: `{monitor_id: "..."}`. Regular fields (queryable but not stream-defining): `organization_id`, `incident_id` (nullable), `event_type`, `status_code`, `response_time_ms`, `error_class`, `region`, `body_sha256`, `monitor_type`, `fingerprint`.

Nested fields: `timings` object, `response_headers` object, `tls` object, `assertions` array, `consensus` object, `redirect_chain` array. Response `body` as top-level string with `body_truncated: boolean`, `body_bytes_total: integer`.

*Why:* `monitor_id` is low-churn (~1 M active streams max at scale). `incident_id` is high-churn (millions of incidents lifetime) — keeping it as regular-not-stream field avoids stream-table explosion. Queries by `incident_id` use VL's standard filter path, which is fast enough for point lookups.

*Pitfall avoided:* status_code or region as stream fields would multiply cardinality by the number of buckets/regions; VL docs explicitly warn against this.

### D6. Incident trace pointer via `vl_trace_id` uuid

When MonitorProcess creates an incident, it:
1. Generates a uuid via `Uniq.UUID.uuid7/0` at `Incident.create_changeset/1` time.
2. Persists it on the incident row as `vl_trace_id`.
3. Emits a VL event `event_type: :incident_created` carrying that same `trace_id` as a regular field.
4. Later lifecycle events (update, resolve, upgrade) reuse the same `trace_id`.

Incident detail view queries VL with filter `{monitor_id=X} | filter trace_id=Y` and returns the matching events in chronological order.

*Why:* Uuid is a cheap stable pointer. Keeps Postgres row small (~16 bytes). Decouples Postgres and VL — VL can be rebuilt from a backup without Postgres needing a migration.

*Alternative:* Store `started_at` + `monitor_id` as the composite lookup key. Rejected — VL's stream-filter pattern is more natural with an explicit trace_id.

**Known limitation — mid-streak check events carry `trace_id: nil`:** `MonitorProcess` state does not currently hold the `vl_trace_id` of the active incident. Lifecycle events (created / upgraded / resolved) carry the trace_id because they have the incident in hand; mid-streak `:check_failed` events emitted during an ongoing incident carry `trace_id: nil` because the GenServer has only `state.incident_id` to work with. Consequence: to reconstruct the full forensic timeline for incident `T`, the reader queries VL by `incident_id = <incident's id>` (for mid-streak checks) OR `trace_id = T` (for lifecycle events), then merges. Acceptable for v1; the follow-up tightening is D6.1 below.

### D6.1. Follow-up: propagate `vl_trace_id` into MonitorProcess state

When the VL adapter goes live (tasks §5–§8), add `:vl_trace_id` to the `MonitorProcess` struct. Populate it from `init/1` hydration (`Monitoring.get_ongoing_incident/1` already returns the full incident row — read `vl_trace_id` from there) and from the Task.Supervisor child after a successful `Monitoring.create_incident/1` (passing the new id back via a `GenServer.cast({:set_trace_id, id})`). Reset to `nil` on the UP-path evaluate_result clauses (alongside `incident_id`).

*Why not now:* Requires a small round-trip via cast from the incident-creation Task to the owning MonitorProcess. Without VL deployed, `trace_id` on events has no reader, so this is cosmetic until §5–§8 ship. Wiring it up now without VL would add code paths that aren't exercised by any test.

### D7. Body cap: 64 KB in VL, SHA256 in every event

Response body truncated to 64 KB before emit. Full SHA256 of the original body goes into `body_sha256` field. If the body is > 64 KB, `body_truncated: true` and `body_bytes_total` reflects the real size. VL's 10–15× compression keeps the on-disk cost reasonable.

*Why:* 64 KB captures ~99% of error bodies (JSON stack traces, 5xx HTML pages). SHA256 enables cross-incident deduplication analysis at query time without needing the full body.

*Alternative:* Hash-only with body in object storage. Rejected — VL holds bodies efficiently; object-storage overhead isn't worth saving a few GB.

### D8. `Uptrack.Failures.DualAdapter` for cutover

During the transition window (spanning this change's deploy → validation), both adapters fire:

```elixir
defmodule Uptrack.Failures.DualAdapter do
  @behaviour Uptrack.Failures

  def record(event) do
    Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
      VictoriaLogsAdapter.record(event)
    end)
    PostgresAdapter.record(event)
  end
end
```

Postgres is the durability primary during cutover; VL runs in shadow. After a week or two of VL stability, flip config to `VictoriaLogsAdapter` only and eventually drop the Postgres table in a separate change.

*Why:* Zero-downtime migration. Postgres is the escape hatch if VL has bugs. Matches standard dual-write pattern (Stripe Idempotency, Stripe Writer-Reader splits, etc.).

## Risks / Trade-offs

- **Risk:** vlagent on a given app node dies; forensic events lost until it's back. → **Mitigation:** vlagent has on-disk buffer (`-remoteWrite.tmpDataPath`), survives brief outages; longer outages drop events (fire-and-forget). Meta-monitoring alert on `rate(vlagent_remotewrite_errors_total[5m])`.
- **Risk:** VL on nbg3 *and* nbg4 both unreachable (network partition, cluster-wide issue). → **Mitigation:** vlagent buffers up to `-remoteWrite.maxDiskUsagePerURL` per destination, then drops. Meta-monitoring covers this.
- **Risk:** Stream cardinality explosion if monitor_id becomes unbounded (e.g., test suite creating monitors without cleanup). → **Mitigation:** `vl_streams_created_total` metric alerted on rate > 1k/hr in prod.
- **Risk:** VL bug causes data corruption, and Postgres adapter has already been disabled. → **Mitigation:** DualAdapter stays on for at least 2 weeks post-deploy; weekly `vmbackup` to R2. Separate change drops Postgres only after that validation window.
- **Risk:** Body-hash redaction: a body containing a credential is hashed and stored. If someone reverses the hash against a rainbow table, credential leaks. → **Mitigation:** SHA256 is one-way; rainbow-table risk is acceptable for structured body samples. GDPR/PII redaction is a separate concern.
- **Trade-off:** Dedup means we miss some DOWN checks in the forensic log (by design). If a monitor fails 50 times with identical errors, we write once. Acceptable; the counter is in VM.
- **Trade-off:** Per-GenServer dedup state resets on process restart (post-deploy). First failure after restart always writes. Acceptable — slightly higher write volume in the minute after deploy, then settles.
- **Trade-off:** No native per-stream retention means all VL data shares one retention period. Chosen: 2 y global. Raw stream + incident-scoped events share the same TTL — slightly more disk than strictly necessary (~15 GB/node extra at 1 M), still trivial vs. budget.

## Migration / Rollout

1. **Infra phase** (NixOS, colmena apply sequential): install VL on nbg3, verify `systemctl is-active victorialogs && curl localhost:9428/ping` → install on nbg4 → same checks. Install vlagent on nbg1 → verify it's writing to both → on nbg2.
2. **Schema phase**: add `vl_trace_id` column to incidents via Ecto migration.
3. **Code phase**: deploy Elixir with `failures_adapter: DualAdapter` (both backends active). Observe VL disk growth + Postgres growth stays as before.
4. **Validation window**: 7 days of dual-write. Compare row counts between Postgres and VL (`expect approx equal modulo dedup`). Query incident detail from both, confirm payloads match.
5. **Cutover**: config flip to `VictoriaLogsAdapter` only. Postgres writes stop. Monitor for 48h.
6. **Cleanup** (separate change): drop `monitor_check_failures` table and cleanup worker.

**Rollback path:** config flip back to `PostgresAdapter` at any time. VL data continues to accumulate but is effectively ignored by read path. Postgres resumes durable primary.
