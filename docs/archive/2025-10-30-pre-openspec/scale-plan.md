Excellent architectural thinking! Having 2 VictoriaMetrics clusters provides redundancy
   and allows independent scaling. Let me design this properly.

  Architecture: 2 Independent VM Clusters

  Why 2 Clusters?

  1. ✅ High Availability - One cluster fails, the other serves queries
  2. ✅ Zero-downtime upgrades - Upgrade one cluster at a time
  3. ✅ Independent scaling - Add vmstorage to whichever cluster needs capacity
  4. ✅ Geographic redundancy - Cluster 1 (Poland) + Cluster 2 (Austria)

  Initial Deployment: Minimum Viable 2-Cluster Setup

  Option A: Lean Start (6 nodes) - $31.38/mo - $40.68/mo

  ┌─────────────────────────────────────────────────────────┐
  │ Cluster 1 (Primary) - Poland (3 nodes)                  │
  ├─────────────────────────────────────────────────────────┤
  │ Node 1: vmstorage1 + vminsert1 + vmselect1             │
  │ Node 2: vmstorage2 + vminsert2                          │
  │ Node 3: vmstorage3 + vmselect2                          │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ Cluster 2 (Secondary) - Austria (3 nodes)               │
  ├─────────────────────────────────────────────────────────┤
  │ Node 4: vmstorage1 + vminsert1 + vmselect1             │
  │ Node 5: vmstorage2 + vminsert2                          │
  │ Node 6: vmstorage3 + vmselect2                          │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ PostgreSQL (separate, or co-located)                    │
  ├─────────────────────────────────────────────────────────┤
  │ Option 1: Add 2 dedicated nodes (+$10.46 - $13.56)     │
  │ Option 2: Co-locate on VM nodes (no extra cost)        │
  └─────────────────────────────────────────────────────────┘

  Cost:
  - Hostkey only: 6 × $5.23 = $31.38/mo (VM only)
  - Netcup only: 6 × $6.78 = $40.68/mo (VM only)
  - Add PostgreSQL: +$10.46 (Hostkey) or +$13.56 (Netcup)

  Option B: Production-Ready (8 nodes) - $41.84/mo - $54.24/mo

  ┌─────────────────────────────────────────────────────────┐
  │ Cluster 1 (Primary) - Poland                            │
  ├─────────────────────────────────────────────────────────┤
  │ Node 1: vmstorage1 + vminsert1                          │
  │ Node 2: vmstorage2 + vmselect1                          │
  │ Node 3: vmstorage3 + vminsert2 + vmselect2             │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ Cluster 2 (Secondary) - Austria                         │
  ├─────────────────────────────────────────────────────────┤
  │ Node 4: vmstorage1 + vminsert1                          │
  │ Node 5: vmstorage2 + vmselect1                          │
  │ Node 6: vmstorage3 + vminsert2 + vmselect2             │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ PostgreSQL (dedicated nodes)                            │
  ├─────────────────────────────────────────────────────────┤
  │ Node 7: PostgreSQL Primary (Poland)                     │
  │ Node 8: PostgreSQL Replica (Austria)                    │
  └─────────────────────────────────────────────────────────┘

  Cost:
  - Hostkey: 8 × $5.23 = $41.84/mo
  - Netcup: 8 × $6.78 = $54.24/mo
  - Hybrid: 6× Hostkey + 2× Netcup = $31.38 + $13.56 = $44.94/mo

  Data Flow: Dual-Write Pattern

  ┌──────────────────┐
  │  Monitor Check   │
  │   (45s interval) │
  └────────┬─────────┘
           │
           ▼
  ┌──────────────────────────────────────────┐
  │   Application (Elixir)                   │
  │   - Writes to PostgreSQL                 │
  │   - Dual-write to both VM clusters       │
  └────┬──────────────────────┬──────────────┘
       │                      │
       ▼                      ▼
  ┌─────────────────┐    ┌─────────────────┐
  │  VM Cluster 1   │    │  VM Cluster 2   │
  │  (Poland)       │    │  (Austria)      │
  │  vminsert:8428  │    │  vminsert:8428  │
  └─────────────────┘    └─────────────────┘

  Dual-write implementation:
  # In your monitoring check worker
  defp write_metrics(check) do
    metrics = format_metrics(check)

    # Write to both clusters in parallel
    Task.async(fn ->
      VictoriaMetrics.write(cluster: :primary, metrics: metrics)
    end)

    Task.async(fn ->
      VictoriaMetrics.write(cluster: :secondary, metrics: metrics)
    end)
    |> Task.await_many()
  end

  Scaling Path: Adding vmstorage Nodes

  Stage 1: Current (100 users × 100 monitors)

  Each cluster:
  - 3 vmstorage nodes
  - ~35 GB storage usage (15 months retention)
  - 333 samples/sec per cluster

  Stage 2: Growth to 300 users × 100 monitors (3x scale)

  Add 1 vmstorage per cluster:

  Cluster 1 (Poland):
  ├── Node 1: vmstorage1 + vminsert1
  ├── Node 2: vmstorage2 + vmselect1
  ├── Node 3: vmstorage3 + vminsert2 + vmselect2
  └── Node 9: vmstorage4 ← NEW!

  Cluster 2 (Austria):
  ├── Node 4: vmstorage1 + vminsert1
  ├── Node 5: vmstorage2 + vmselect1
  ├── Node 6: vmstorage3 + vminsert2 + vmselect2
  └── Node 10: vmstorage4 ← NEW!

  New cost: +$10.46/mo (Hostkey) or +$13.56/mo (Netcup)

  Stage 3: Growth to 500 users × 100 monitors (5x scale)

  Add more vmstorage:

  Each cluster: 6 vmstorage nodes
  Total nodes: 6 VM per cluster + 2 PG = 14 nodes

  Cost: 14 × $5.23 = $73.22/mo (Hostkey)

  Stage 4: Heavy scale (1000+ users)

  Separate vminsert/vmselect/vmstorage:

  Cluster 1:
  ├── 2× vminsert (dedicated)
  ├── 3× vmselect (dedicated)
  └── 8× vmstorage (dedicated)

  Cluster 2: Same as Cluster 1

  Total: 26 nodes = ~$136/mo (Hostkey)

  How to Add vmstorage Node (Step-by-Step)

  1. Provision New Node

  # On new node (e.g., node-9)
  docker run -d \
    --name vmstorage4 \
    -v /data/vmstorage:/storage \
    -p 8482:8482 \
    -p 8400:8400 \
    -p 8401:8401 \
    victoriametrics/vmstorage:latest \
    -storageDataPath=/storage \
    -retentionPeriod=15M \
    -memory.allowedPercent=60

  2. Update vminsert Configuration

  Before (3 vmstorage nodes):
  docker run -d \
    --name vminsert \
    -p 8480:8480 \
    victoriametrics/vminsert:latest \
    -storageNode=node1:8400 \
    -storageNode=node2:8400 \
    -storageNode=node3:8400

  After (4 vmstorage nodes):
  docker run -d \
    --name vminsert \
    -p 8480:8480 \
    victoriametrics/vminsert:latest \
    -storageNode=node1:8400 \
    -storageNode=node2:8400 \
    -storageNode=node3:8400 \
    -storageNode=node9:8400  # ← NEW!

  3. Update vmselect Configuration

  docker run -d \
    --name vmselect \
    -p 8481:8481 \
    victoriametrics/vmselect:latest \
    -storageNode=node1:8401 \
    -storageNode=node2:8401 \
    -storageNode=node3:8401 \
    -storageNode=node9:8401  # ← NEW!

  4. Restart vminsert/vmselect

  # On nodes running vminsert
  docker restart vminsert

  # On nodes running vmselect
  docker restart vmselect

  No downtime! Existing vmstorage nodes keep serving queries while you restart
  vminsert/vmselect.

  Cost Comparison: 2-Cluster Architecture

  | Setup          | Provider | Nodes | Monthly | Annual  | Notes                     |
  |----------------|----------|-------|---------|---------|---------------------------|
  | Lean (VM only) | Hostkey  | 6     | $31.38  | $376.56 | Co-locate PostgreSQL      |
  | Lean (VM only) | Netcup   | 6     | $40.68  | $488.16 | Co-locate PostgreSQL      |
  | Production     | Hostkey  | 8     | $41.84  | $502.08 | Dedicated PG nodes        |
  | Production     | Netcup   | 8     | $54.24  | $650.88 | Dedicated PG nodes        |
  | Hybrid         | Mixed    | 8     | $44.94  | $539.28 | 6× Hostkey + 2× Netcup PG |

  My Recommendation: Hybrid Approach

  Initial: 8-Node Production Setup @ $44.94/mo

  Poland (Hostkey) - Cluster 1:
  ├── Node 1: vmstorage1 + vminsert1          ($5.23)
  ├── Node 2: vmstorage2 + vmselect1          ($5.23)
  └── Node 3: vmstorage3 + vminsert2 + vmselect2  ($5.23)

  Austria (Netcup) - Cluster 2:
  ├── Node 4: vmstorage1 + vminsert1          ($6.78)
  ├── Node 5: vmstorage2 + vmselect1          ($6.78)
  └── Node 6: vmstorage3 + vminsert2 + vmselect2  ($6.78)

  Poland (Hostkey):
  └── Node 7: PostgreSQL Primary              ($5.23)

  Austria (Netcup):
  └── Node 8: PostgreSQL Replica              ($6.78)

  Total: $44.94/mo

  Why this works:
  - ✅ 2 independent VM clusters (HA!)
  - ✅ Geographic redundancy (Poland + Austria ~15-20ms)
  - ✅ PostgreSQL on beefier Netcup nodes in Austria (6 vCPU + 256GB)
  - ✅ VM Cluster 1 on cheaper Hostkey (cost optimization)
  - ✅ Can scale each cluster independently
  - ✅ Reasonable cost ($540/year)

  Scaling Path:

  | Users | Monitors | vmstorage/cluster | Total Nodes | Cost/mo |
  |-------|----------|-------------------|-------------|---------|
  | 100   | 10K      | 3                 | 8           | $44.94  |
  | 300   | 30K      | 4                 | 10          | $55.40  |
  | 500   | 50K      | 6                 | 14          | $76.32  |
  | 1000  | 100K     | 8                 | 18          | $97.24  |

  Want me to create the NixOS configuration files for this 2-cluster setup with easy
  scaling?
