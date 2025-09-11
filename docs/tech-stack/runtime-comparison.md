# Runtime Comparison for Uptime Monitoring (Elixir, Go, Rust)

## Workload Character
- I/O and storage bound: outbound HTTP/TCP, small responses, DB writes.
- CPU rarely the bottleneck unless you add heavy parsing/crypto.
- Success depends on jittered scheduling, bounded concurrency, and how much you write to storage.

## Elixir/Phoenix (BEAM)
- Strengths: supervision trees, fault tolerance, back-pressure, clustering.
- Excellent for orchestrating millions of timers, retries, and async workers.
- Networking: `Req` (Finch under the hood) provides pooled HTTP with low overhead.
- Operational: fast iteration, clear failure isolation, rolling restarts.
- When to choose: control plane + workers in one cohesive system; fast to build reliable schedulers.

## Go
- Strengths: lightweight goroutines, efficient `net/http`, tiny static binaries, easy multi-region rollout.
- You implement supervision/retry patterns explicitly or via libraries.
- When to choose: you want very small stateless worker binaries at the edge; the team is Go-first.

## Rust
- Strengths: tight memory usage, predictable performance, excellent for CPU-intensive hotspots.
- Costs: higher complexity and build times; for uptime (I/O bound) benefits are marginal.
- Use via Ports or separate service if needed; avoid long-running NIFs for heavy work.

## Throughput Reality (language-agnostic)
- 1,000,000 monitors @ 1/min ⇒ ~16,667 checks/s.
- Concurrency ≈ rate × latency: at 300–500 ms, you need ~5,000–8,300 open sockets cluster-wide.
- DB is the limiter if you write every probe; network egress grows with response size.

## Practical Recommendation
- Start with Elixir/Phoenix for control plane + worker pool.
- Use jitter, bounded concurrency, short timeouts, and state-change + aggregates storage.
- If your ops model prefers tiny edge workers, have Phoenix orchestrate and Go workers execute probes via internal HTTP/queue.
- Use Rust only for niche CPU-bound modules and keep them isolated (Ports/services).

## Bottom Line
- Elixir vs Go vs Rust won’t change HTTP latency or DB write costs.
- Pick based on team expertise and operational model. Optimize data model and scheduling first; that’s where 10–100× gains come from.

