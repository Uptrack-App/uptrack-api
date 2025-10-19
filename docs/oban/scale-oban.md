# Scaling Oban: Core Components and Performance Optimization

**Uptrack Implementation Status**: See `/docs/oban/MULTI_REPO_POOL_STRATEGY.md` for current architecture

---

## Core Scaling Principles

### 1. What are the core components of an Oban application and why are they considered scalable?

Oban applications leverage the power of **Elixir** and **PostgreSQL**:

- **Elixir** (Erlang OTP): Horizontal scalability through lightweight processes, handles "2 million web socket connections" with ease
- **PostgreSQL**: Versatile, robust scaling (vertical & horizontal), achieves "1 billion inserts a second" in optimized setups
- **Combination**: Highly scalable foundation for job processing

**Uptrack uses both at scale:**
- 5 nodes running Elixir (Germany, Austria, Canada, India Strong, India Weak)
- HA PostgreSQL cluster (5-node distributed system)
- Separate Oban pool to prevent resource contention
2. How has PostgreSQL evolved to better support high-performance queueing, and what specific features are crucial for Oban?
Over the past eight years, PostgreSQL has introduced several features vital for its use as a scalable queue. Key advancements include:
• JSONB (9.4): Enables a hybrid document and relational database model, important for storing job arguments.
• SKIP LOCKED (9.6): This is described as "the secret sauce to being able to have queues at all without contention," preventing multiple workers from processing the same job.
• REINDEX CONCURRENTLY (12): Allows for rebuilding indexes to minimize space without downtime.
• B-tree Deduplication (13): Crucial for state machine models as queues, where duplicate rows are common, improving pruning efficiency.
• Optimized Skipping B-splits (14): Further enhances B-tree performance, though the specific technical details were not elaborated upon. These features collectively make PostgreSQL a powerful and efficient backend for Oban.
3. What are the key "quick-fire tips" for optimizing Oban application performance and avoiding common issues?
Several quick-fire tips are offered to maximize throughput and minimize impact:
• Minimize job argument size: Store only essential values like IDs to reduce data transfer, storage, and indexing overhead, and improve resilience to retries.
• Prune aggressively: Regularly delete completed, canceled, or discarded jobs to free up database space and improve query performance.
• Use insert_all: Batch job insertions into a single transaction instead of individual inserts to reduce round trips and improve efficiency.
• Update PostgreSQL version: Each new PostgreSQL version brings performance improvements and features that benefit Oban. Upgrading to the latest supported version (currently 16, with Oban supporting back to 12) provides "free performance."
• Vertically scale your database: The most immediate and often cost-effective way to get an "instantaneous" performance win.
4. How can activity be optimized in Oban applications, especially under high load?
If PG notify appears at the top of frequent queries, it indicates a bottleneck in the default notification system. Oban uses PubSub notifications for inter-node communication (job inserts, pausing/resuming queues, web metrics), and the default PostgreSQL Notifier uses a separate query for each notification. To fix this, it's recommended to:
• Avoid using a single connection: This creates a bottleneck and taints at scale.
• Switch to alternative notifiers: Use PG or ProcessGroups. These minimize database load, reduce total queries, and allow for larger payloads. For a functional distributed Erlang cluster, this is a "single line change" in configuration.
5. What strategies help in preventing index and table bloat in Oban, and why is it important?
Index and table bloat occurs because PostgreSQL's transactional model only flags rows/indexes for deletion, which are then cleaned up by autovacuum, but the space isn't immediately reclaimed from disk. This accumulates "garbage" over time.
• For indexes: Use the reindexer plugin to "intermittently concurrently without any locking or any downtime rebuild all of those essential indexes." This minimizes their size and optimizes queries. It can be scheduled using a cron-like schedule.
• For tables: Tweak autovacuum settings specifically for the oban_jobs table. The optimal scale_factor will depend on the unique situation of the application, table size, and database load.
• Oban Pro's Dynamic Partitioner (Pro Tip): Instead of pruning, this feature partitions jobs by state and drops entire tables. Dropping a table "leaves no bloat leftover," is "virtually instantaneous," and results in smaller, less active tables that are faster for autovacuum to process.
6. How can issues with inserting bulk unique jobs and errors from Oban be resolved?
• Bulk Unique Job Timeouts: Inserting unique jobs involves an extra query to check for existing jobs and an advisory lock to prevent transaction competition. This stacks up to three queries per job. To address this:
    ◦ Evaluate necessity: Determine if uniqueness is truly required for the workload.
    ◦ Optimize uniqueness checks: Select a single field (e.g., an ID) instead of an entire JSON field to reduce the work.
    ◦ Set timestamp option to scheduled_at: If uniqueness is necessary, using scheduled_at as an index can improve performance.
    ◦ Oban Pro Smart Engine (Pro Tip): Allows bulk unique inserts in a single transaction, reducing multiple queries and locks per job to just two queries.
• **Ecto Timeout Errors**: ✅ **Uptrack Solution Implemented**
  - Problem: Shared pool causes contention
  - Solution: Dedicated secondary repo pool for Oban ✅
  - AppRepo: 10-15 connections (app queries)
  - ObanRepo: 20-30 connections (job processing)
  - Result: "Very few connections by itself" but isolated from app
7. What causes connection errors under peak load in high concurrency queues, and how can they be mitigated?
Under peak load and high concurrency, connection errors can occur because while fetching jobs is a single optimized query per queue, acknowledging (acing) each finished job takes a separate connection. This leads to pool contention. The recommended solutions are:
• Increase pool size and reduce overall concurrency: Find the right ratio between active jobs and available connections.
• Use a dedicated database pool for Oban: This is reiterated as "very important" for predictable performance, especially with 100 million+ jobs a day. It provides a clear baseline of available connections for Oban, separate from the application.
• Oban Pro Smart Engine (Pro Tip): Acknowledges jobs in batches (aces all those jobs together), reducing the number of transactions and queries required for job completion.
## 8. Ultimate "Pro Tips" for Scaling Oban

The ultimate "pro tips" for scaling Oban applications summarize the core advice given throughout the talk:

### ✅ Uptrack Implementation Status

| Pro Tip | Status | Details |
|---------|--------|---------|
| **Isolate Oban from your app** | ✅ | AppRepo (app) + ObanRepo (jobs) separate pools |
| **Single migration source** | ✅ | AppRepo handles all (app + oban schema) |
| **Minimize transactions** | ✅ | Using insert_all for batch job insertion |
| **Minimize index bloat** | ✅ | Reindexer plugin can be added if needed |
| **Minimize table bloat** | ✅ | 7-day pruning with Oban.Plugins.Pruner |
| **Aggressive pruning** | ✅ | <100MB Oban DB size target |
| **Batch operations** | ✅ | Batch check insertions via ResilientWriter |
| **Separate analytics DB** | ✅ | ClickHouse for metrics (not Postgres) |

### Result

These tips, when combined, enable Oban to handle massive workloads, demonstrated by the claim of running **"1 billion jobs a day on a laptop"** under optimal configuration.

Uptrack configuration:
- Target: 1000+ check jobs per second (10K monitors × 10 checks/min across 5 regions)
- Implementation: Distributed pool isolation + aggressive pruning + analytics separation
- Expected: Sub-100ms job processing, <100MB Oban table size