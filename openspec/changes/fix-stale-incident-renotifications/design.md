## Context

Each active monitor has a long-lived `Uptrack.Monitoring.MonitorProcess` GenServer that tracks consecutive failures and "alerted this streak" in memory. The DB's `incidents` table is the durable source of truth — a partial unique index `incidents_one_ongoing_per_monitor_idx` (migration `20260420100000`) enforces at most one `ongoing` row per monitor.

Today `MonitorProcess.init/1` starts with empty in-memory state and never reads the `incidents` table. `Monitoring.create_incident/1` papers over the unique conflict by returning `{:ok, existing}` so callers can't tell creation from collision. Together, any restart leaks the in-memory "there's an incident" flag and the next real failure re-alerts on the old incident.

Production impact: 23 stale `ongoing` rows, some 12 days old. Each app restart re-alerts all of them to customers via Telegram/email.

## Goals / Non-Goals

**Goals:**
- No "new incident" alerts fire for incidents that already exist in the DB.
- After a restart, a monitor that has recovered resolves its in-DB `ongoing` incident on its next UP check (and sends a *resolution* alert, which is correct).
- Cleanup path for the 23 existing stale rows runs once, post-deploy.
- Zero schema change; rely on the existing unique index.

**Non-Goals:**
- Reshaping the `MonitorProcess` state machine or consensus logic.
- Adding a startup-time reconciliation sweep over all monitors (hydration at `init/1` is enough — the process already re-spawns per monitor).
- Revisiting the `check_worker.ex` vs `MonitorProcess` duality. Both call `create_incident/1`, so fixing the callee covers both paths.
- Changing user-visible notification formatting or cadence.

## Decisions

**Decision 1: Change `create_incident/1` to return `{:error, :already_ongoing}` on unique conflict instead of `{:ok, existing}`.**
- *Why:* Callers need to distinguish "I just created this" from "it was already there." `{:ok, existing}` conflates them and was the direct trigger for the spurious `broadcast_incident_created` + `send_incident_alerts` calls.
- *Alternative considered:* Add a third return shape like `{:ok, :existing, incident}`. Rejected — a two-element tuple means touching fewer call sites and matches idiomatic Ecto failure modes. Callers that cared about the existing row can still fetch it via `get_ongoing_incident/1`.
- *Blast radius:* Two internal call sites (`check_worker.ex:517`, `monitor_process.ex:384`). Both currently pattern-match only `{:ok, incident}` and `{:error, changeset}` — the new `{:error, :already_ongoing}` just needs a `log + no-op` branch. No public API or test fixture relies on the previous `{:ok, existing}` shape.

**Decision 2: Hydrate `MonitorProcess` from DB at `init/1`.**
- *Why:* The GenServer's streak/incident flags are the only signal for whether the "up → resolve" clause (line 250) fires. If they're wrong at boot, the DB incident is effectively orphaned until another down→up cycle happens *within the same process lifetime* — which for most monitors never happens.
- *Hydration rule:* If `get_ongoing_incident(monitor.id)` returns a row, set `alerted_this_streak: true`, `incident_id: existing.id`, `consecutive_failures: confirmation_threshold`. The confirmation_threshold bump is deliberate — the in-memory model is "we're past threshold, an alert has fired," which is what the running DB state represents.
- *Alternative considered:* Add a startup worker that resolves any `ongoing` incident whose monitor has `consecutive_failures = 0`. Rejected — that's a centralized sweep, can race with normal check flow, and breaks the "MonitorProcess owns its monitor's state" invariant. Per-process hydration is local and idempotent.

**Decision 3: SQL UPDATE for the 23 stale rows, not a migration.**
- *Why:* This is data cleanup, not schema evolution. A migration would re-run on every fresh DB and codify production-specific garbage. Run it once via `psql` after both nodes are on the new code (so fresh incidents won't immediately be re-orphaned).
- *Ordering:* Deploy first, then cleanup. If cleanup ran before the hydration fix was live, an active monitor could re-create the same stale incident between cleanup and deploy.

## Risks / Trade-offs

- **Risk:** A monitor that was genuinely still down at restart gets hydrated as `alerted_this_streak: true`, so no fresh "DOWN" alert fires even though a reminder might be appropriate. → **Mitigation:** This is the intended behavior — the existing reminder system (`IncidentReminder` in `maybe_trigger_alert`) handles repeat notifications. Suppressing an *initial-alert duplicate* is the whole point.
- **Risk:** A `check_worker.ex` code path (Oban job) races a `MonitorProcess` and both try to `create_incident`. Previously both would get `{:ok, incident}` (one created, one got the existing). Now one gets `{:ok, new}` and the other gets `{:error, :already_ongoing}`. → **Mitigation:** That's actually correct — only one alert fires, which is what users want. The `log + no-op` branch handles the losing racer cleanly.
- **Risk:** Hydrating with `consecutive_failures: confirmation_threshold` means the first UP check after restart immediately matches the resolve clause. If that first check is a transient success (flap), we resolve and immediately re-alert on the next fail. → **Mitigation:** Acceptable — that's the same behavior as any normal resolve→re-fire cycle, and it represents a legitimate state transition. The alternative (suppress resolve for N checks after restart) adds more state than it saves.
- **Trade-off:** We're adding one extra DB read per `MonitorProcess` start. At ~hundreds of monitors and init happening rarely, negligible.
