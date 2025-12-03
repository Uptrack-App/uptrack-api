
  PostgreSQL Scaling Options - Decision Tree

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    WHEN DO YOU NEED TO SCALE?                          │
  ├─────────────────────────────────────────────────────────────────────────┤
  │                                                                         │
  │  Current capacity (single PostgreSQL):                                  │
  │  └─ ~10,000-50,000 writes/sec (depends on hardware)                    │
  │                                                                         │
  │  Your current load (10K monitors @ 30s interval):                       │
  │  └─ ~333 writes/sec = 0.4% of capacity                                 │
  │                                                                         │
  │  You need to scale when: writes/sec > 10,000                           │
  │  That's: 300,000+ monitors (you're at 10K now)                         │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    4 WAYS TO SCALE POSTGRESQL                          │
  ├─────────────────────────────────────────────────────────────────────────┤
  │                                                                         │
  │  1. VERTICAL SCALING (Bigger Server)                                   │
  │     ├─ What: More CPU, RAM, faster SSD                                 │
  │     ├─ Scales: Both reads AND writes                                   │
  │     ├─ Limit: ~50K writes/sec (hardware limit)                         │
  │     ├─ Cost: €7→€20→€50/mo (just upgrade VPS)                          │
  │     └─ When: First option, always try this first                       │
  │                                                                         │
  │  2. READ REPLICAS (More Servers, Same Data)                            │
  │     ├─ What: Copy data to replica servers                              │
  │     ├─ Scales: READS only (not writes!)                                │
  │     ├─ Limit: Writes still go to 1 primary                             │
  │     ├─ Cost: €7/mo per replica                                         │
  │     └─ When: Dashboard queries slow, many users reading                │
  │                                                                         │
  │  3. CITUS SHARDING (Split Data Across Servers)                         │
  │     ├─ What: Distribute tables by organization_id                      │
  │     ├─ Scales: Both reads AND writes (horizontally)                    │
  │     ├─ Limit: Practically unlimited                                    │
  │     ├─ Cost: €7/mo per worker node                                     │
  │     └─ When: >10K writes/sec (300K+ monitors)                          │
  │                                                                         │
  │  4. CONNECTION POOLING (PgBouncer)                                     │
  │     ├─ What: Reuse database connections                                │
  │     ├─ Scales: Number of connections (not throughput)                  │
  │     ├─ Limit: Doesn't increase write capacity                          │
  │     ├─ Cost: Free (already included in your setup)                     │
  │     └─ When: "too many connections" errors                             │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘

  Your Scaling Path (Simplified)

  NOW (10K monitors, 333 writes/sec):
  ├─ Single PostgreSQL on Netcup G12 (€7/mo)
  ├─ Citus extension installed (ready, not used)
  ├─ No workers needed
  └─ Capacity: 30x headroom

  GROWTH (100K monitors, 3,333 writes/sec):
  ├─ Same setup, still fine
  ├─ Maybe upgrade to bigger VPS (€20/mo)
  └─ Capacity: 3-10x headroom

  BIG (300K+ monitors, 10,000+ writes/sec):
  ├─ Add first Citus worker (€7/mo)
  ├─ Data automatically redistributes
  └─ Capacity: 2x (now 20K writes/sec)

  HUGE (1M+ monitors, 33,000+ writes/sec):
  ├─ Add more Citus workers
  ├─ 4 workers = ~50K writes/sec
  └─ Keep adding as needed

  Key Point

  Read replicas ≠ Write scaling

                      ┌─────────────┐
                      │   PRIMARY   │ ← ALL writes go here
                      │  (1 server) │
                      └──────┬──────┘
                             │
                ┌────────────┼────────────┐
                ▼            ▼            ▼
          ┌─────────┐  ┌─────────┐  ┌─────────┐
          │ Replica │  │ Replica │  │ Replica │  ← Only handle READS
          └─────────┘  └─────────┘  └─────────┘

  Adding replicas = More read capacity
  Adding replicas ≠ More write capacity

  Citus sharding = Write scaling

          ┌──────────────────────────────────────┐
          │           COORDINATOR                │
          │    (routes queries to workers)       │
          └──────────────┬───────────────────────┘
                         │
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
     ┌──────────┐  ┌──────────┐  ┌──────────┐
     │ Worker 1 │  │ Worker 2 │  │ Worker 3 │
     │ Org 1-33 │  │ Org 34-66│  │ Org 67-99│  ← Each handles its own writes
     └──────────┘  └──────────┘  └──────────┘

  Adding workers = More write capacity (linear scaling)

  Summary

  | Scaling Type          | Scales Reads | Scales Writes | When to Use       |
  |-----------------------|--------------|---------------|-------------------|
  | Vertical (bigger VPS) | ✅            | ✅             | First, always     |
  | Read replicas         | ✅            | ❌             | Slow dashboards   |
  | Citus sharding        | ✅            | ✅             | >10K writes/sec   |
  | PgBouncer             | ❌            | ❌             | Connection errors |

  For your current stage: Just use single PostgreSQL with Citus extension ready. You
  won't need workers until 300K+ monitors.
