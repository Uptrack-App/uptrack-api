## Context

Uptrack has two independent alerting code paths that both watch the same monitor state:

1. **`MonitorProcess`** — a GenServer per monitor. Gets per-region check results via `pg` broadcasts, feeds them into `Consensus`, decides UP/DOWN, and dispatches alerts via `maybe_trigger_alert/1`.
2. **`CheckWorker`** — an Oban job. Runs a direct check, writes the `MonitorCheck`, and in `handle_check_result/2` also creates incidents and dispatches alerts when `consecutive_failures` crosses threshold.

Both paths were building duplicate state machines. After the `fix-stale-incident-renotifications` change, the unique index `incidents_one_ongoing_per_monitor_idx` prevents duplicate DB rows, but it doesn't prevent duplicate *alerts* fired simultaneously before the index trips — the callers still both reach `send_incident_alerts`. The audit also found several alert-emitting paths that forgot to check maintenance windows (`MonitorProcess`, degradation, reminders, heartbeat).

Taken together: the codebase has seven places that could dispatch a "monitor down / degraded / still-down" alert. Some gate on maintenance, some don't. Two of them race. This change rationalizes the seven paths into a consistent contract.

## Goals / Non-Goals

**Goals:**
- A single source of truth for "should we alert on this monitor failure" — `MonitorProcess`.
- Every alert-emitting path gates on `Maintenance.under_maintenance?/2`.
- Consensus never fires a verdict on minority data.
- Heartbeat missed-check incidents actually notify users.
- Degradation and DOWN don't collide in the DB.
- Escalation never pages an already-resolved or acknowledged incident.
- Delivery retries are idempotent where the provider allows it.

**Non-Goals:**
- Redesigning the GenServer state machine.
- Removing `CheckWorker` entirely (still needed for UP-path DB persistence and cross-region incident resolution on shared check results).
- Introducing an `incident_type` column for degradation vs. DOWN (handled in-place).
- Reworking escalation policy configuration or the reminder system's cadence logic.
- Adding new notification channels.

## Decisions

**D1. `MonitorProcess` owns incident creation and initial down alerts; `CheckWorker` keeps only UP-path responsibilities.**
- *Why:* `MonitorProcess` already owns cross-region consensus, which is where the "is this monitor really down" decision must happen. Letting `CheckWorker` also create incidents means a single-region transient failure can race past the consensus check. Demoting `CheckWorker` to UP-path only (persist check, reset counter, resolve ongoing incidents if the check was UP) keeps the pipeline healthy without duplicating the DOWN decision.
- *Alternative considered:* Remove `CheckWorker.handle_check_result/2` entirely and route everything through `MonitorProcess`. Rejected because `CheckWorker` is still reached via Oban retries and direct scheduler invocations, and its UP-path logic (reset counter, resolve ongoing incidents) is a useful belt-and-suspenders when the GenServer has been restarted and is mid-hydration.
- *Alternative considered:* Keep both paths, add a distributed lock / row-level advisory lock on `create_incident`. Rejected as over-engineered — single-owner is simpler, and the consensus path is already the correct home for the decision.
- *Blast radius:* Demoting `CheckWorker` means any monitor check that runs *only* through the Oban path (e.g. if `MonitorProcess` is crash-looping) won't alert until the GenServer recovers. That's acceptable — the supervisor restarts the GenServer within seconds, and the test suite + existing deploy verification catches crash loops.

**D2. Gate every alert-emitting path on `Maintenance.under_maintenance?/2`.**
- *Why:* This is a literal consistency fix, not a design choice. Currently three paths skip the gate. The gate is cheap (one DB query, cacheable) and semantically correct in all places it's missing.
- *Placement:* Call the check as close to dispatch as possible — right before `Alerting.send_incident_alerts/2`, `send_incident_reminder/2`, or `Alerting.send_resolution_alerts/2`. Don't gate *incident creation* on maintenance — we still want to track that a check failed during maintenance for the dashboard; we just don't page. This matches the existing `CheckWorker` pattern on line 500 which *skips* incident creation during maintenance — OK to diverge and always create the incident, since customer-visible output is the alert, not the row.
- *Decision on "skip create or skip alert":* Skip both creation and alert dispatch during maintenance (matches existing `CheckWorker` semantics). Keeps the incident history clean — a maintenance-window failure isn't an incident.

**D3. Consensus quorum: require `>50%` of expected regions before any timeout verdict.**
- *Why:* The current rule (`timeout AND ≥2 results`) hard-codes 2 as the floor. In a 3-region setup, 2 of 3 down is genuinely a majority. In a 5-region setup, 2 of 5 is not. Majority-of-expected scales correctly and collapses to "all regions" for 1-region monitors.
- *Alternative considered:* Require 100% of expected regions to have responded before any verdict (no timeout shortcut). Rejected — a genuinely broken region would block all verdicts, including UP, indefinitely.
- *Alternative considered:* Require 100% for DOWN verdicts, any majority for UP verdicts. Rejected as asymmetric complexity without clear wins — a monitor that reports UP in the majority and DOWN in one region is probably region-network-flaky, not a real incident, so UP-majority is correct. A monitor that reports DOWN in the majority is probably really down.
- *Edge case:* Single-region monitors. Majority-of-1 is 1 — no change from current behavior.

**D4. Degradation → DOWN upgrades the existing incident's cause in-place.**
- *Why:* Introducing an `incident_type` column or separate tables would be the "clean" long-term answer, but requires a migration, a UI story for filtering, and cross-team sign-off. The in-place upgrade is a single line in `check_worker.ex`/`monitor_process.ex` and has zero migration cost. It's a pragmatic choice; we can revisit if degradation becomes a major product surface.
- *Contract:* When a hard DOWN check arrives and `get_ongoing_incident/1` returns an incident whose `cause` indicates degradation, update that incident's `cause` to the hard-down error message. Do not send a second "incident created" alert (avoid duplicate pages); instead, enqueue an "incident updated" alert so users still see the escalation from degraded to down.
- *Non-goal:* Tracking the degradation→down transition as a separate history event. That belongs in `incident_updates`, which already exists — add an update row with a `transition: "degraded_to_down"` metadata key.

**D5. Escalation re-verifies before paging.**
- *Why:* Escalation runs on a delay (minutes). The incident it was created for can be resolved, acknowledged, or state-changed in the interim. Re-reading right before dispatch is the cheapest correct guard.
- *Implementation:* In `EscalationWorker.perform/1`, after scheduling delay has elapsed and before invoking any alert-dispatch function, re-run `Monitoring.get_incident/1` and check `status == "ongoing"` and `acknowledged_at == nil`. If either fails, log and return `:ok` (don't retry — the incident changed legitimately).

**D6. Delivery idempotency via `notification_deliveries.id`.**
- *Why:* Some channels (Telegram) dedupe by `{chat_id, message_body, timestamp-window}`; most don't. Passing a stable token (the delivery row ID) lets retries land in the same "slot" when the provider supports it, and be treated as a new message otherwise. Pragmatic partial fix.
- *Scope:* Telegram first (it's where we've seen duplicates). Email has native message-id handling. Slack/Discord webhook deduplication is provider-dependent and out of scope.

## Risks / Trade-offs

- **Risk:** After D1, a bug in `MonitorProcess` (e.g. crash loop during consensus) silently suppresses all DOWN alerts. → **Mitigation:** Supervisor restarts within seconds; hydration (just shipped) re-initializes state correctly; add a test that verifies `MonitorProcess.init/1` + a single UP→DOWN→threshold cycle fires exactly one alert; monitor uptrack-itself for missing expected alerts (meta-monitoring covered elsewhere).
- **Risk:** D3 (quorum) delays legitimate alerts if a monitor is genuinely down and enough regions are slow/dropped. → **Mitigation:** The `@consensus_timeout_ms` is already 10 seconds. If a majority hasn't reported in 10 seconds, the monitor *itself* is suspect (network-path issue), and a false-positive suppression is the right failure mode.
- **Risk:** D4 (in-place upgrade) means the incident's `started_at` reflects the degradation start, not the hard-down start. A user reading the dashboard sees "incident started 15m ago" when hard-down was only 2m ago. → **Mitigation:** Document this in the incident-update row so audit trails have both timestamps; accept the trade-off for now.
- **Risk:** D5 (escalation re-verify) opens a new DB read per escalation dispatch. → **Mitigation:** Escalations are rare (seconds apart at most), DB read is cheap. Negligible.
- **Trade-off:** D6 is partial — only Telegram gets idempotency tokens in this pass. Acceptable since Telegram is where duplicates were observed; other providers can be addressed if reports surface.

## Migration / Rollout

1. Implement and test all changes locally.
2. Deploy `nbg1` first, observe logs for:
   - No "Confirmed DOWN" log lines from `CheckWorker` (only from `MonitorProcess`).
   - No alerts fired during the current maintenance windows (verify against `app.maintenance_windows` active rows).
   - Consensus "insufficient data" log lines when regions time out.
3. Deploy `nbg2`, re-verify.
4. No data migration needed. Existing `ongoing` incidents continue behaving normally.
5. Rollback path: revert the Elixir commits and redeploy. No DB state to undo.
