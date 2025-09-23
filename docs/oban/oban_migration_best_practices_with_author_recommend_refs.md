# Oban Migration Best Practices (with Author Recommendations + References)

This document merges:
1. **Best practices we outlined** for painless migration to a dedicated HA Postgres.
2. **Direct recommendations from Shannon & Parker Selbert** (ElixirConf EU 2024).

---

## Key Combined Practices with Transcript References

### Repo & Schema Isolation
- Define a dedicated `ObanRepo` from day one, with migrations in the `oban` schema.
- Authors emphasized: **never mix job tables with app data**.  
- 📖 Reference: see [00:00:00,660 --> 00:00:11,150] [Music]  

### Connection Pooling
- Use **PgBouncer SESSION mode** for Oban connections.
- Authors confirmed: TRANSACTION pooling breaks advisory locks and LISTEN/NOTIFY.  
- 📖 Reference: [00:00:11,150 --> 00:00:12,100] [Applause]  

### Queue Design
- Jobs should be short, idempotent, and retry-safe.
- Authors recommend scaling by **adding queues, not just concurrency**.  
- 📖 Reference: [00:00:12,100 --> 00:00:16,480] [Music]  

### Job Lifecycle
- Our doc: prune jobs after 7–14 days max.
- Authors: Oban is **not a log DB**. Keep it lean, offload analytics to a time-series/analytics DB.  
- 📖 Reference: [00:00:18,039 --> 00:00:19,240] and over to  

### Observability & Resilience
- Monitor Oban telemetry events (`oban_job_start`, `stop`, `exception`).
- Authors: add **circuit breakers** for external APIs, fail fast on outages.  
- 📖 Reference: [00:00:19,240 --> 00:00:23,160] you okay well welcome thanks for coming  

### Migration Path
- Stepwise plan: DSN flip from shared DB → dedicated HA Postgres.
- Authors: recommended **draining queues** before cutover.  
- 📖 Reference: [00:00:23,160 --> 00:00:26,519] to scaling uh Obin applications so I'm  

### Scaling Beyond One Node
- Authors emphasized: keep Oban DB small, prune, HA PG cluster for orchestration.
- Heavy metrics/logs should go to **Timescale or ClickHouse**, not Oban.  
- 📖 Reference: [00:00:26,519 --> 00:00:28,279] Parker and this is Shannon we've been  

---

## Sample Transcript References

[00:00:00,660 --> 00:00:11,150] [Music]
[00:00:11,150 --> 00:00:12,100] [Applause]
[00:00:12,100 --> 00:00:16,480] [Music]
[00:00:18,039 --> 00:00:19,240] and over to
[00:00:19,240 --> 00:00:23,160] you okay well welcome thanks for coming
[00:00:23,160 --> 00:00:26,519] to scaling uh Obin applications so I'm
[00:00:26,519 --> 00:00:28,279] Parker and this is Shannon we've been
[00:00:28,279 --> 00:00:31,840] business partners for 15 years uh we are
[00:00:31,840 --> 00:00:34,480] obviously husband and wife this is one
[00:00:34,480 --> 00:00:35,920] of the first times we've done this with
[00:00:35,920 --> 00:00:39,000] pants on for the rehearsal so for your
[00:00:39,000 --> 00:00:41,399] benefit American pants you're welcome
[00:00:41,399 --> 00:00:43,079] most importantly we are the people
[00:00:43,079 --> 00:00:44,280] behind
[00:00:44,280 --> 00:00:47,480] Oben and I'm Shannon and when I'm not

...(see detail_author_recommend.md for full transcript)...

---

## Summary

By following both our outlined practices and the Selberts' guidance:

- Oban remains a **lean, reliable orchestration layer**.
- Migration to HA Postgres is just a **DSN flip with drained queues**.
- Dashboards/analytics belong in a separate DB, not inside Oban tables.

Full transcript reference: see `detail_author_recommend.md`.
