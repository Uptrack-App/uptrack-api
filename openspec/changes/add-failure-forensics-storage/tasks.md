## 1. Elixir scaffolding (no infra dependency)

- [ ] 1.1 Create `lib/uptrack/failures.ex` defining the `Uptrack.Failures` behaviour (`@callback record/1`), the `Uptrack.Failures.Event` struct (all fields), and a public `record/1` that resolves the adapter via `Application.get_env(:uptrack, :failures_adapter)` and delegates.
- [ ] 1.2 Create `lib/uptrack/failures/event.ex` — the event struct with `new_from_check/2` helper that builds the struct from a `MonitorCheck` + monitor context, including body truncation to 64 KB and SHA256 hashing.
- [ ] 1.3 Create `lib/uptrack/failures/fingerprint.ex` — pure module with `compute/1` returning `{status_code, error_class, body_sha256}` tuple and `error_class/1` classifying errors into `:dns | :tcp | :tls | :http | :timeout | :assertion | :unknown`.
- [ ] 1.4 Create `lib/uptrack/failures/postgres_adapter.ex` implementing the behaviour by writing to existing `app.monitor_check_failures` via the existing `Uptrack.Monitoring.CheckFailures.record/1` pattern. This is the "legacy" path.
- [ ] 1.5 Create `lib/uptrack/failures/noop_adapter.ex` that returns `:ok` without writing. Used in test env.
- [ ] 1.6 Update `config/config.exs` to set `failures_adapter: Uptrack.Failures.PostgresAdapter` as default; `config/test.exs` to `NoopAdapter`.

## 2. MonitorProcess integration

- [ ] 2.1 Extend the `MonitorProcess` struct with `:last_failure_fingerprint` and `:last_failure_recorded_at` fields (both default nil).
- [ ] 2.2 In `MonitorProcess.record_result/1`, after persisting the check, call a new private `maybe_emit_failure/1` that computes the fingerprint, compares to state, and calls `Uptrack.Failures.record/1` on first-seen-or-changed fingerprints or when >10 minutes since last emission. Update state accordingly.
- [ ] 2.3 In `MonitorProcess.handle_incident_dispatch/2` and the resolve clause (line ~259), after a successful `Monitoring.create_incident/1` or `resolve_all_ongoing_incidents/1`, call `Uptrack.Failures.record/1` with an event carrying `event_type: "incident_created"` / `"incident_resolved"` / `"incident_upgraded"`. These bypass dedup.
- [ ] 2.4 Remove the direct `Uptrack.Monitoring.CheckFailures.record(check)` call in `MonitorProcess.record_result/1` (it's now routed through the Failures behaviour). Leave the `CheckFailures` module intact — the PostgresAdapter uses it under the hood.

## 3. Schema migration

- [ ] 3.1 Create migration `priv/app_repo/migrations/<ts>_add_vl_trace_id_to_incidents.exs` adding `vl_trace_id :uuid` column to `app.incidents`, default null.
- [ ] 3.2 Update `Uptrack.Monitoring.Incident` schema: add `vl_trace_id` field, include in `changeset/2` cast list.
- [ ] 3.3 Update `Monitoring.create_incident/1` to generate a uuid v7 (`Uniq.UUID.generate(7)`) and set it on the attrs before insert, unless a value is explicitly provided.

## 4. VictoriaMetrics counter + histogram

- [ ] 4.1 In `Uptrack.Metrics.Batcher` (or wherever existing metrics flow), add emission of `uptrack_check_failures_total{monitor_id, status_code, region}` on DOWN checks.
- [ ] 4.2 Add `uptrack_check_duration_ms{monitor_id, status, region}` histogram on every check (UP or DOWN).
- [ ] 4.3 Ensure labels are bounded: `status_code` bucketed to `{2xx, 3xx, 4xx, 5xx, other}` rather than raw codes to control cardinality. `region` is the check region. `monitor_id` is fine (bounded by monitor count).

## 5. VictoriaLogs adapter — sharded Batcher with per-shard Gun connection (no HTTP pool)

- [ ] 5.1 Create `lib/uptrack/failures/batcher.ex` — plain `Supervisor` that starts N named shards under a `:one_for_one` strategy. Shard count resolved from `config :uptrack, :failures_shard_count` with default `System.schedulers_online()`. Children registered as `Uptrack.Failures.Batcher.Shard.0` … `Shard.N-1` via explicit atom names.
- [ ] 5.2 Create `lib/uptrack/failures/batcher/shard.ex` — `GenServer`. State carries `:buffer` (iodata list), `:lines`, `:bytes`, `:conn` (Gun pid or nil), `:pending` (map of `stream_ref => :in_flight`), `:dropped` counter. `init/1` opens a Gun connection to `localhost:9429` via `:gun.open/3` (protocols `:http` — HTTP/1.1 keep-alive; upgrade to `:http2` if vlagent supports it). Schedules the flush tick.
- [ ] 5.3 Implement `handle_cast({:write, event}, state)`: encode event via `VlClient.encode/1`, append to iodata buffer, bump counters. If `lines >= 1000` or `bytes >= 1_048_576`, immediate flush. Otherwise accumulate.
- [ ] 5.4 Implement `handle_info(:flush, state)`: if buffer non-empty, call `do_flush/1`; always reschedule the 1-second timer.
- [ ] 5.5 Implement `do_flush/1`: `IO.iodata_to_binary` the buffer, `:gun.post(conn, ~c"/insert/jsonline?_stream_fields=monitor_id", headers, body)`, register the returned `stream_ref` into `state.pending`, reset buffer.
- [ ] 5.6 Implement `handle_info({:gun_response, conn, sref, _, status, _}, state)` and `{:gun_data, ...}` / `{:gun_trailers, ...}`: remove `sref` from `pending` on completion; log a warning on non-2xx; no retry (vlagent handles retry).
- [ ] 5.7 Implement `handle_info({:gun_down, ...}, state)` and `{:gun_up, ...}`: buffer writes continue; log at `:info`. Gun's internal `retry:` option handles reconnection.
- [ ] 5.8 Implement overflow discipline in `handle_cast({:write, _}, state)`: if `lines > 5000` or `bytes > 5_242_880`, drop the oldest buffered event (O(1) via reversed iodata semantics — snip from the tail of the iodata list), increment `state.dropped`, log at `:warn` every 1000 drops.
- [ ] 5.9 Create `lib/uptrack/failures/router.ex` with pure `pick_shard/2`: `:erlang.phash2(monitor_id, shard_count)`. Lookup shard-count once from `:persistent_term` (initialized by the Batcher supervisor at boot).
- [ ] 5.10 Rewrite `lib/uptrack/failures/vl_client.ex` to expose only `encode/1` (a pure function producing a trailing-newline-terminated NDJSON line) and `fetch_by_trace_id/3` (used by the forensic read endpoint, not by the write path). Remove `insert/1` — Gun usage lives in the Shard.
- [ ] 5.11 Rewrite `lib/uptrack/failures/victoria_logs_adapter.ex` to be a one-liner: `def record(event), do: GenServer.cast(Router.pick_shard(event.monitor_id), {:write, event})`. No Task, no direct HTTP.
- [ ] 5.12 Keep `lib/uptrack/failures/dual_adapter.ex` as designed — delegates to `PostgresAdapter.record/1` (synchronous) and `VictoriaLogsAdapter.record/1` (cast to shard).
- [ ] 5.13 Add `config :uptrack, Uptrack.Failures, vlagent_host: "localhost", vlagent_port: 9429` in `config/config.exs`. Runtime env override via `VLAGENT_URL` in `config/runtime.exs`.
- [ ] 5.14 Wire `Uptrack.Failures.Batcher` into `Uptrack.Application` supervision tree, after `Uptrack.TaskSupervisor` and before monitor processes start.
- [ ] 5.15 Emit Batcher observability metrics to VM: `uptrack_forensic_events_enqueued_total`, `uptrack_forensic_events_dropped_total`, `uptrack_forensic_batches_flushed_total`, `uptrack_forensic_batch_lines_bucket` (histogram of batch sizes), `uptrack_forensic_flush_duration_ms` (histogram).

## 6. Incident forensic read path

- [ ] 6.1 Add `lib/uptrack/failures/vl_query.ex` — queries VL via HTTP GET against the first reachable VL node (nbg3, fall back to nbg4). Filter by `{monitor_id=X} AND trace_id=Y`, returns events ordered by timestamp.
- [ ] 6.2 Add controller action in `UptrackWeb.Api.IncidentController` — `GET /api/incidents/:id/forensic`. Loads the incident by id (org-scoped), calls `VlQuery.fetch_by_trace_id/2`, renders events or graceful fallback per spec scenarios.
- [ ] 6.3 Add route in `UptrackWeb.Router` under the authenticated `/api` scope.
- [ ] 6.4 Add JSON view for the forensic response shape.

## 7. Infra — VictoriaLogs on nbg3 and nbg4 (NixOS)

- [ ] 7.1 Create `infra/nixos/modules/services/victorialogs.nix` — NixOS module defining the `victorialogs` service. Systemd unit, user, data dir `/var/lib/victorialogs`, binds `-httpListenAddr` to the Tailscale IP, `-retentionPeriod=2y`, `-storageDataPath=/var/lib/victorialogs/data`, `TimeoutStartSec=30s`, `Restart=on-failure`.
- [ ] 7.2 Wire the module into `infra/nixos/regions/europe/netcup-nbg3/default.nix` and `…/netcup-nbg4/default.nix`.
- [ ] 7.3 Open port 9428 only on the Tailscale interface (firewall rule).
- [ ] 7.4 Deploy: `cd uptrack-api && nix run github:zhaofengli/colmena -- apply --on nbg3`. Verify `systemctl is-active victorialogs` and `curl http://<tailscale-ip>:9428/ping` returns `OK`.
- [ ] 7.5 Deploy nbg4 with same verification.
- [ ] 7.6 **Set `-http.idleConnTimeout=10m`** on the VL service (via NixOS module ExecStart args). Default 60 s would force the Gun shards to reconnect on every quiet period; 10 m handles typical idle gaps with zero churn.

## 8. Infra — no vlagent (direct dual-write from app)

Dropped from scope. `victorialogs` at nixpkgs 1.35.0 does not ship `vlagent`. We write directly from the Elixir shards to both nbg3 and nbg4 via per-shard Gun connections. Alerts to add in vmalert:

- [ ] 8.1 Alert: `rate(uptrack_forensic_events_dropped_total[5m]) > 0` → warn
- [ ] 8.2 Alert: `rate(uptrack_forensic_batch_flush_errors_total[5m]) > 0.1 per second` → warn — indicates Gun -> VL post failures
- [ ] 8.3 Alert: `up{job="victorialogs"} == 0` on either nbg3 or nbg4 → warn
- [ ] 8.4 Follow-up (if drops become sustained): revisit vlagent via flake override to a newer VL release that ships it.

## 9. Cutover configuration

- [ ] 9.1 Flip `config/prod.exs` (or agenix-managed env) to `failures_adapter: Uptrack.Failures.DualAdapter`. This enables writing to both Postgres and VL in production.
- [ ] 9.2 Deploy the Elixir change (migration + app code) to nbg1, verify no crashes, deploy to nbg2.
- [ ] 9.3 Observability: add to Grafana (or whatever dashboard exists) panels for `vl_rows_ingested_total`, `vl_storage_data_size_bytes`, `vlagent_remotewrite_errors_total`. Baseline during the validation window.

## 10. Tests

- [ ] 10.1 `test/uptrack/failures/event_test.exs`: body truncation, SHA256 correctness, struct shape.
- [ ] 10.2 `test/uptrack/failures/fingerprint_test.exs`: fingerprint tuples, error_class classification.
- [ ] 10.3 `test/uptrack/failures_test.exs`: adapter resolution from config; DualAdapter writes to both; NoopAdapter returns `:ok`.
- [ ] 10.4 `test/uptrack/monitoring/monitor_process_test.exs` extension: fingerprint dedup behavior — consecutive identical failures emit once; fingerprint change emits again; >10 min since last emission emits again.
- [ ] 10.5 Incident lifecycle events test: `incident_created` / `incident_resolved` bypass dedup and include `vl_trace_id`.
- [ ] 10.6 Controller test for `/api/incidents/:id/forensic` graceful fallback when no events exist (use NoopAdapter / stub VL response).
- [ ] 10.7 `mix test` — all green.

## 11. Validation & cleanup

- [ ] 11.1 After 7 days of DualAdapter dual-write in prod, compare Postgres row counts to VL event counts (expected: VL ≤ Postgres due to dedup, but both should grow proportionally).
- [ ] 11.2 Open an incident, verify `/api/incidents/:id/forensic` returns the VL events matching the Postgres-written rows for the same `trace_id`.
- [ ] 11.3 Flip config to `failures_adapter: Uptrack.Failures.VictoriaLogsAdapter` (VL-only). Deploy. Monitor 48h for regressions.
- [ ] 11.4 Follow-up change (NOT in this scope): drop `app.monitor_check_failures` table and `Uptrack.Monitoring.CheckFailureCleanupWorker`.
- [ ] 11.5 Archive both OpenSpec changes (`fix-stale-incident-renotifications`, `close-false-alert-gaps`, `add-failure-forensics-storage`) once stable.

## 12. Known-issue follow-ups (from review)

- [ ] 12.1 **trace_id propagation** (design.md D6.1): add `:vl_trace_id` to `MonitorProcess` struct; hydrate from `Monitoring.get_ongoing_incident/1` in `init/1`; set via `GenServer.cast({:set_trace_id, id})` after `Monitoring.create_incident/1` succeeds; reset to `nil` on UP-path `evaluate_result` clauses. Replace `trace_id_for(_state), do: nil` with `trace_id_for(state), do: state.vl_trace_id`. Deferrable until §5 (VL adapter) is shipping — without a reader, it's cosmetic.
- [ ] 12.2 **Release-note the dashboard grouping change**: the `/api/monitor/:id/failures` view becomes fingerprint-grouped once this change ships. Draft copy: "The failure log now groups identical failures by fingerprint to reduce noise. A single entry represents one or more consecutive checks with the same `{status_code, error_class, body_sha256}`."
- [ ] 12.3 **Investigate `gitlab` monitor misconfigured degradation threshold** (`2ms`): separate from this change, but noticed during validation. Either fix the user's settings or add validation preventing degradation thresholds below the 50 ms floor. File as its own task.
