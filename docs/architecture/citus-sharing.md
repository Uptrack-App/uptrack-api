
⏺ PostgreSQL Horizontal Scaling Alternatives

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    HORIZONTAL SCALING OPTIONS                          │
  ├─────────────────────────────────────────────────────────────────────────┤
  │                                                                         │
  │  1. CITUS (PostgreSQL Extension)                                       │
  │  2. Application-Level Sharding (DIY)                                   │
  │  3. NewSQL Databases (CockroachDB, YugabyteDB)                        │
  │  4. Foreign Data Wrappers (postgres_fdw)                              │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘

  Comparison

  | Option       | PostgreSQL Compatible | Effort | Cost       | Best For     |
  |--------------|-----------------------|--------|------------|--------------|
  | Citus        | 100% (extension)      | Low    | Free/Pro   | Growing apps |
  | App Sharding | 100% (vanilla PG)     | High   | Free       | Full control |
  | CockroachDB  | ~95% wire compat      | Medium | Free/Cloud | Global apps  |
  | YugabyteDB   | ~95% wire compat      | Medium | Free/Cloud | Global apps  |
  | postgres_fdw | 100% (built-in)       | High   | Free       | Simple cases |

  ---
  1. Citus (Already Discussed)

  Pros: Native PostgreSQL, Ecto works unchanged, free tier
  Cons: Some query limitations, complex JOINs need care

  ---
  2. Application-Level Sharding (DIY)

  You manage sharding in your Elixir code:

  # config/config.exs - Multiple repos
  config :uptrack, Uptrack.Repo.Shard0,
    hostname: "pg-shard-0.internal"

  config :uptrack, Uptrack.Repo.Shard1,
    hostname: "pg-shard-1.internal"

  config :uptrack, Uptrack.Repo.Shard2,
    hostname: "pg-shard-2.internal"

  # lib/uptrack/shard_router.ex
  defmodule Uptrack.ShardRouter do
    @shards [Uptrack.Repo.Shard0, Uptrack.Repo.Shard1, Uptrack.Repo.Shard2]

    def repo_for(organization_id) do
      shard_index = :erlang.phash2(organization_id, length(@shards))
      Enum.at(@shards, shard_index)
    end

    def create_monitor(org_id, attrs) do
      repo = repo_for(org_id)
      repo.insert(%Monitor{organization_id: org_id, url: attrs.url})
    end

    def get_monitors(org_id) do
      repo = repo_for(org_id)
      repo.all(from m in Monitor, where: m.organization_id == ^org_id)
    end

    # Cross-shard query (expensive - hits all shards)
    def count_all_monitors do
      @shards
      |> Task.async_stream(fn repo -> repo.aggregate(Monitor, :count) end)
      |> Enum.reduce(0, fn {:ok, count}, acc -> acc + count end)
    end
  end

  Pros:
  ├─ Full control over routing
  ├─ No vendor lock-in
  ├─ Works with vanilla PostgreSQL
  └─ No query limitations

  Cons:
  ├─ YOU write all sharding logic
  ├─ YOU handle rebalancing when adding shards
  ├─ YOU handle cross-shard queries
  ├─ Migrations run on each shard separately
  └─ More code to maintain

  Who uses this: Instagram, Pinterest, Notion (before they grew huge)

  ---
  3. CockroachDB (Distributed SQL)

  Drop-in PostgreSQL replacement with automatic sharding:

  # config/config.exs - Just point to CockroachDB
  config :uptrack, Uptrack.Repo,
    hostname: "cockroachdb.internal",
    port: 26257,
    database: "uptrack"

  # Your Ecto code stays the same!
  def create_monitor(attrs) do
    %Monitor{}
    |> Monitor.changeset(attrs)
    |> Repo.insert()  # CockroachDB handles distribution automatically
  end

  Pros:
  ├─ Automatic sharding (no code changes)
  ├─ Automatic rebalancing
  ├─ Multi-region by default
  ├─ Strong consistency (serializable)
  └─ PostgreSQL wire protocol

  Cons:
  ├─ Not 100% PostgreSQL (some features missing)
  ├─ Higher latency for writes (~10-50ms vs ~1ms)
  ├─ More resource hungry
  ├─ Oban may need adjustments
  └─ Cloud pricing can be expensive

  Who uses this: DoorDash, Netflix, Bose

  ---
  4. YugabyteDB (Distributed PostgreSQL)

  Similar to CockroachDB but closer to PostgreSQL:

  # Same config as PostgreSQL
  config :uptrack, Uptrack.Repo,
    hostname: "yugabyte.internal",
    port: 5433,
    database: "uptrack"

  Pros:
  ├─ More PostgreSQL compatible than CockroachDB
  ├─ Automatic sharding
  ├─ Can run on your own VPS
  ├─ Free and open source
  └─ Better Oban compatibility

  Cons:
  ├─ Still not 100% PostgreSQL
  ├─ Higher latency than vanilla PG
  ├─ Complex to self-host (3+ nodes minimum)
  └─ Less mature than CockroachDB

  Who uses this: Kroger, Fanatics, Narvar

  ---
  5. Foreign Data Wrappers (postgres_fdw)

  Built-in PostgreSQL feature for querying remote servers:

  -- On coordinator
  CREATE EXTENSION postgres_fdw;

  CREATE SERVER shard1 FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg-shard-1.internal', dbname 'uptrack');

  CREATE SERVER shard2 FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg-shard-2.internal', dbname 'uptrack');

  -- Create foreign tables
  CREATE FOREIGN TABLE monitors_shard1 (
    id bigint, organization_id bigint, url text
  ) SERVER shard1 OPTIONS (table_name 'monitors');

  -- Query across shards using UNION
  SELECT * FROM monitors_shard1
  UNION ALL
  SELECT * FROM monitors_shard2;

  Pros:
  ├─ Built into PostgreSQL (no extensions)
  ├─ Simple concept
  └─ Full control

  Cons:
  ├─ Manual everything
  ├─ No automatic routing
  ├─ Poor performance for large queries
  ├─ YOU manage sharding logic
  └─ Basically DIY with extra steps

  ---
  Recommendation for Uptrack

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         DECISION TREE                                   │
  ├─────────────────────────────────────────────────────────────────────────┤
  │                                                                         │
  │  Do you need global multi-region writes?                               │
  │  ├─ YES → CockroachDB or YugabyteDB                                    │
  │  └─ NO ↓                                                               │
  │                                                                         │
  │  Do you want full control and hate dependencies?                       │
  │  ├─ YES → Application-level sharding (DIY)                             │
  │  └─ NO ↓                                                               │
  │                                                                         │
  │  Do you want easy scaling with PostgreSQL compatibility?               │
  │  └─ YES → Citus ✅ (Your current choice)                               │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘

  For Uptrack, Citus is the right choice because:

  1. You're already using PostgreSQL + Ecto
  2. Your data has natural shard key (organization_id)
  3. You don't need global multi-region writes
  4. Single region (Nuremberg) is fine for now
  5. Citus is free and battle-tested
  6. Zero code changes to your Ecto queries

  When to reconsider:

  | If This Happens                               | Consider               |
  |-----------------------------------------------|------------------------|
  | Need writes in Asia AND Europe simultaneously | CockroachDB/YugabyteDB |
  | Hit Citus query limitations                   | App-level sharding     |
  | Acquired by company using different DB        | Migration project      |