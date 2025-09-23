Scaling Oban: Core Components and Performance Optimization
1. What are the core components of an Oban application and why are they considered scalable?
Oban applications leverage the power of Elixir and PostgreSQL. Elixir, built on the Erlang OTP (Open Telecom Platform), is renowned for its horizontal scalability due to its process model and its ability to handle a massive number of concurrent connections (demonstrated by "2 million web stock connections" and the "template of doom" for I/O scalability). PostgreSQL is chosen for its versatility and robust scaling capabilities, both vertically (on a single server) and horizontally (across multiple servers), with reported achievements like "1 billion inserts a second in optimized situations." The combination of these two technologies forms a highly scalable foundation for Oban.
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
• Ecto Timeout Errors: Oban uses connections from the application's repo pool. If the pool is busy, Oban can be starved of connections, leading to timeouts. Conversely, a very busy Oban can starve the application. The solution is to:
    ◦ Set up a dedicated secondary repo pool for Oban: This isolates Oban's database queries, preventing contention with the application. It's easy to configure and Oban generally uses "very few connections by itself."
7. What causes connection errors under peak load in high concurrency queues, and how can they be mitigated?
Under peak load and high concurrency, connection errors can occur because while fetching jobs is a single optimized query per queue, acknowledging (acing) each finished job takes a separate connection. This leads to pool contention. The recommended solutions are:
• Increase pool size and reduce overall concurrency: Find the right ratio between active jobs and available connections.
• Use a dedicated database pool for Oban: This is reiterated as "very important" for predictable performance, especially with 100 million+ jobs a day. It provides a clear baseline of available connections for Oban, separate from the application.
• Oban Pro Smart Engine (Pro Tip): Acknowledges jobs in batches (aces all those jobs together), reducing the number of transactions and queries required for job completion.
8. What are the ultimate "pro tips" for scaling Oban applications based on the overall discussion?
The ultimate "pro tips" for scaling Oban applications summarize the core advice given throughout the talk:
• Isolate Oban from your app: Use a dedicated database connection pool for Oban to prevent resource contention.
• Minimize extra transactions and queries: Batch operations like inserts and acknowledgements (insert_all, Oban Pro's Smart Engine) to reduce round trips to the database.
• Minimize index bloat: Regularly reindex using the reindexer plugin.
• Minimize table bloat: Tune autovacuum settings for the oban_jobs table, or use Oban Pro's Dynamic Partitioner for bloat-free table drops.
These tips, when combined, enable Oban to handle massive workloads, demonstrated by the claim of running "1 billion jobs a day on a laptop" under optimal configuration.