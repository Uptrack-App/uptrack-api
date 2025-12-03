# GCP e2-standard-2 Performance Benchmark Report

**Date**: 2025-12-02
**Project**: Uptrack Infrastructure Comparison
**Tested Node**: GCP e2-standard-2 - 34.130.208.111
**Comparison**: GCP vs Hostkey Italy vs Hetzner vs Contabo vs Oracle Cloud

---

## Executive Summary

GCP e2-standard-2 offers **fastest CPU** among all tested providers but **poor disk I/O** and is **12x more expensive** than Hostkey Italy. For database and storage-intensive workloads, Hostkey remains the better choice.

### Key Findings:
- **CPU**: GCP is fastest (1330 events/sec) - 41% faster than Hostkey, 28% faster than Hetzner
- **Disk I/O**: GCP is slowest (175 MB/s write) - Hostkey is 4.7x faster, Hetzner is 8x faster
- **Network**: GCP has excellent download (3.5 Gbps) - only Hetzner is faster
- **Storage**: GCP has least space (10 GB) - Hostkey has 11x more, Contabo has 15x more
- **Price**: GCP is most expensive (~$55/month) - Hostkey is 12x cheaper

### Overall Winner: **Hostkey Italy** 🏆 (Best Value)
### CPU Winner: **GCP e2-standard-2** 🥇 (Fastest CPU)
### Budget Winner: **Oracle Cloud Free Tier** 🆓 (Free!)

---

## Hardware Specifications

### GCP e2-standard-2 (Montreal) - 34.130.208.111
- **Architecture**: x86_64
- **CPU**: AMD EPYC 7B12 (2 vCPU, 1 core + 2 threads)
- **RAM**: 8 GB
- **Storage**: 10 GB SSD (**88% full - critical!**)
- **Network**: 3.5 Gbps download / 2.7 Gbps upload
- **Price**: ~$50-60/month (estimated)
- **Location**: Montreal, Canada
- **Geekbench 6**: Single-Core 860 / Multi-Core 869
- **Geekbench Link**: https://browser.geekbench.com/v6/cpu/15344739

### Hostkey Italy (eu-b) - 194.180.207.225
- **Architecture**: x86_64
- **CPU**: Intel Xeon Silver 4416+ (2.0 GHz, 30MB Cache)
- **RAM**: 7.7 GB DDR4
- **Storage**: 112 GB NVMe SSD
- **Network**: 1.25 Gbps download / 2.6 Gbps upload
- **Price**: €4.17/month (~$4.50)
- **Location**: Italy (Milan)

### Hetzner Cloud (Germany)
- **Architecture**: ARM64 (aarch64)
- **CPU**: 2 cores @ 50.00 BogoMIPS
- **RAM**: 3.7 GB DDR4/DDR5
- **Storage**: 38 GB NVMe SSD
- **Network**: Up to 20 Gbps
- **Price**: €8/month
- **Location**: Germany

### Contabo VPS (Germany)
- **Architecture**: x86_64
- **CPU**: 3 cores AMD EPYC @ 2.79 GHz
- **RAM**: 7.8 GB DDR4
- **Storage**: 150 GB SSD (SATA)
- **Network**: Up to 1 Gbps
- **Price**: €5.99/month
- **Location**: Germany

### Oracle Cloud Free Tier (India)
- **Architecture**: ARM64 (aarch64)
- **CPU**: 3 OCPU Ampere Altra (ARM64)
- **RAM**: 18 GB
- **Storage**: 46 GB SSD
- **Network**: Variable (1-10 Gbps)
- **Price**: **FREE** (Always Free Tier)
- **Location**: India (Hyderabad)

---

## Performance Benchmarks

### 1. CPU Performance

| Provider | Events/sec | vs GCP | vs Hostkey | Rank |
|----------|------------|--------|------------|------|
| **GCP e2-standard-2** | **1330** | baseline | +41% | 🥇 1st |
| **Hetzner ARM64** | ~1038 | -22% | +10% | 🥈 2nd |
| **Hostkey Italy** | 940 | -29% | baseline | 🥉 3rd |
| **Oracle ARM64** | ~900* | -32% | -4% | 4th |
| **Contabo** | ~365 | -73% | -61% | 5th |

*Oracle estimated based on ARM64 Ampere performance

**Raw Output (GCP)**:
```
sysbench cpu --cpu-max-prime=20000 --threads=1 run
events per second: 1330.43
total time: 10.0002s
```

**Analysis**:
- GCP's AMD EPYC 7B12 is **fastest CPU** among all providers
- GCP is **41% faster** than Hostkey, **28% faster** than Hetzner
- GCP is **3.6x faster** than Contabo
- Excellent for CPU-intensive workloads

**Winner**: 🥇 **GCP** (pure speed)

---

### 2. Disk I/O Performance

#### Write Speed

| Provider | Write Speed | vs Hetzner | vs Hostkey | Rank |
|----------|-------------|------------|------------|------|
| **Hetzner ARM64** | **1400 MB/s** | baseline | +69% | 🥇 1st |
| **Hostkey Italy** | 827 MB/s | -41% | baseline | 🥈 2nd |
| **Contabo** | 173 MB/s | -88% | -79% | 🥉 3rd |
| **GCP e2-standard-2** | 175 MB/s | -88% | -79% | 4th |
| **Oracle ARM64** | ~200 MB/s* | -86% | -76% | 5th |

#### Read Speed

| Provider | Read Speed | vs Hetzner | vs Hostkey | Rank |
|----------|------------|------------|------------|------|
| **Hetzner ARM64** | **2.0 GB/s** | baseline | +11% | 🥇 1st |
| **Hostkey Italy** | 1.8 GB/s | -10% | baseline | 🥈 2nd |
| **Contabo** | 444 MB/s | -78% | -75% | 🥉 3rd |
| **GCP e2-standard-2** | 183 MB/s | -91% | -90% | 5th |
| **Oracle ARM64** | ~300 MB/s* | -85% | -83% | 4th |

*Oracle estimated

**Raw Output (GCP)**:
```bash
# Write
dd if=/dev/zero of=/tmp/testfile bs=1M count=1024 oflag=direct
1073741824 bytes (1.1 GB, 1.0 GiB) copied, 6.12064 s, 175 MB/s

# Read
dd if=/tmp/testfile of=/dev/null bs=1M count=1024 iflag=direct
1073741824 bytes (1.1 GB, 1.0 GiB) copied, 5.87962 s, 183 MB/s
```

**Analysis**:
- GCP disk I/O is **slowest** among all providers
- Hetzner is **8x faster writes** than GCP
- Hostkey is **4.7x faster writes** than GCP
- GCP uses standard persistent SSD, **not NVMe**
- **Critical for databases**: PostgreSQL, VictoriaMetrics will suffer on GCP

**Winner**: 🥇 **Hetzner** (speed) / 🥈 **Hostkey** (value)

---

### 3. Network Performance

| Provider | Download | Upload | Ping | Rank |
|----------|----------|--------|------|------|
| **Hetzner ARM64** | **20 Gbps** | 20 Gbps | <1 ms | 🥇 1st |
| **GCP e2-standard-2** | 3.5 Gbps | 2.7 Gbps | 3 ms | 🥈 2nd |
| **Hostkey Italy** | 1.25 Gbps | 2.6 Gbps | 1.8 ms | 🥉 3rd |
| **Oracle ARM64** | ~1-10 Gbps | ~1-10 Gbps | varies | 4th |
| **Contabo** | ~1 Gbps | ~1 Gbps | <5 ms | 5th |

**Raw Output (GCP)**:
```bash
speedtest-cli --simple
Ping: 3.047 ms
Download: 3480.62 Mbit/s
Upload: 2743.53 Mbit/s
```

**Analysis**:
- Hetzner has **fastest network** (20 Gbps)
- GCP has **2.8x faster download** than Hostkey
- GCP network is excellent for data transfer
- Hostkey has better upload than download (2.6 vs 1.25 Gbps)

**Winner**: 🥇 **Hetzner** (raw speed) / 🥈 **GCP** (among budget providers)

---

### 4. Memory Performance

| Provider | RAM Total | RAM Available | Swap | Rank |
|----------|-----------|---------------|------|------|
| **Oracle ARM64** | **18 GB** | ~17 GB | - | 🥇 1st |
| **GCP e2-standard-2** | 8 GB | 5.2 GB | 0 GB | 🥈 2nd |
| **Contabo** | 7.8 GB | ~7.5 GB | - | 🥉 3rd |
| **Hostkey Italy** | 7.7 GB | 7.3 GB | 4 GB | 4th |
| **Hetzner ARM64** | 3.7 GB | ~3.5 GB | - | 5th |

**Raw Output (GCP)**:
```bash
free -h
               total        used        free      shared  buff/cache   available
Mem:           7.8Gi       2.6Gi       4.1Gi        24Mi       1.4Gi       5.2Gi
Swap:             0B          0B          0B
```

**Analysis**:
- Oracle has **most RAM** (18 GB) - and it's FREE!
- GCP, Contabo, Hostkey are similar (~8 GB)
- GCP has **no swap configured** (risky for OOM situations)
- Hostkey has 4 GB swap configured (safety net)
- Hetzner has least RAM but fastest speed

**Winner**: 🥇 **Oracle** (capacity) / 🥈 **Hostkey** (available + swap)

---

### 5. Storage Capacity

| Provider | Storage | Available | Type | Rank |
|----------|---------|-----------|------|------|
| **Contabo** | **150 GB** | ~143 GB | SATA SSD | 🥇 1st |
| **Hostkey Italy** | 112 GB | 105 GB | NVMe SSD | 🥈 2nd |
| **Oracle ARM64** | 46 GB | ~40 GB | SSD | 🥉 3rd |
| **Hetzner ARM64** | 38 GB | ~35 GB | NVMe SSD | 4th |
| **GCP e2-standard-2** | 10 GB | **1.1 GB ⚠️** | Standard SSD | 5th |

**Raw Output (GCP)**:
```bash
df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       9.7G  8.1G  1.1G  88% /
```

**⚠️ CRITICAL WARNING**: GCP disk is **88% full** with only **1.1 GB free**!
- Immediate action required: expand disk or clean up
- Risk of service failure if disk fills up
- GCP has **least storage** of all providers

**Winner**: 🥇 **Contabo** (capacity) / 🥈 **Hostkey** (NVMe + value)

---

## Price-Performance Analysis

### Cost Comparison

| Provider | Monthly Cost | Annual Cost | Performance Tier | Value |
|----------|--------------|-------------|------------------|-------|
| **Oracle ARM64** | **FREE** | **$0** | Premium Free | 🥇 |
| **Hostkey Italy** | €4.17 | €50 | Premium Budget | 🥈 |
| **Contabo Germany** | €5.99 | €72 | Budget | 🥉 |
| **Hetzner Germany** | €8.00 | €96 | Premium | 4th |
| **GCP e2-standard-2** | ~$55 | ~$660 | Premium Cloud | 5th |

### Performance per Dollar (lower price = better value)

| Metric | Oracle | Hostkey | Hetzner | Contabo | GCP | Best Value |
|--------|--------|---------|---------|---------|-----|------------|
| **CPU Events/$** | ∞ | **225** | 130 | 61 | 24 | **Oracle/Hostkey** |
| **Disk Write/$** | ∞ | **198** | 175 | 29 | 3.2 | **Oracle/Hostkey** |
| **Disk Read/$** | ∞ | **432** | 250 | 74 | 3.3 | **Oracle/Hostkey** |
| **RAM/$** | ∞ | **1.85** | 0.46 | 1.30 | 0.14 | **Oracle** |
| **Storage/$** | ∞ | **26.9** | 4.75 | 25.0 | 0.18 | **Oracle/Hostkey** |

**Key Insights:**
- **Oracle** is FREE with excellent specs - unbeatable value
- **Hostkey** delivers 9-149x better value than GCP across all metrics
- **GCP** is 12x more expensive than Hostkey for similar RAM

---

## Summary Comparison Table (All Providers)

| Metric | GCP | Hostkey | Hetzner | Contabo | Oracle | Winner |
|--------|-----|---------|---------|---------|--------|--------|
| **CPU Speed** | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★☆☆☆ | ★★★★☆ | **GCP** |
| **Disk Write** | ★☆☆☆☆ | ★★★★☆ | ★★★★★ | ★☆☆☆☆ | ★★☆☆☆ | **Hetzner** |
| **Disk Read** | ★☆☆☆☆ | ★★★★★ | ★★★★★ | ★★☆☆☆ | ★★☆☆☆ | **Hetzner/Hostkey** |
| **Network** | ★★★★☆ | ★★★☆☆ | ★★★★★ | ★★☆☆☆ | ★★★☆☆ | **Hetzner** |
| **RAM Capacity** | ★★★★☆ | ★★★★☆ | ★★☆☆☆ | ★★★★☆ | ★★★★★ | **Oracle** |
| **Storage** | ★☆☆☆☆ | ★★★★☆ | ★★☆☆☆ | ★★★★★ | ★★★☆☆ | **Contabo** |
| **Price** | ★☆☆☆☆ | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★★★★ | **Oracle (FREE)** |
| **Value (perf/$)** | ★☆☆☆☆ | ★★★★★ | ★★★★☆ | ★★★☆☆ | ★★★★★ | **Oracle/Hostkey** |

### Rankings by Use Case

| Use Case | 1st | 2nd | 3rd | 4th | 5th |
|----------|-----|-----|-----|-----|-----|
| **CPU-Intensive** | GCP | Hetzner | Hostkey | Oracle | Contabo |
| **Database (I/O)** | Hetzner | Hostkey | Contabo | Oracle | GCP |
| **Storage-Heavy** | Contabo | Hostkey | Oracle | Hetzner | GCP |
| **Memory-Hungry** | Oracle | GCP | Contabo | Hostkey | Hetzner |
| **Best Value** | Oracle | Hostkey | Contabo | Hetzner | GCP |
| **Overall** | **Hostkey** | Oracle | Hetzner | Contabo | GCP |

### Overall Winner: **Hostkey Italy** 🏆 (paid) / **Oracle Cloud** 🆓 (free)

---

## Use Case Recommendations

### Choose GCP e2-standard-2 If:
- ✅ Need **fastest CPU** for compute-intensive tasks
- ✅ Need **fast network** for data transfer
- ✅ Have **budget flexibility** ($50-60/month)
- ✅ Need **managed services** (Cloud SQL, etc.)
- ✅ Already in GCP ecosystem
- ❌ NOT for databases (slow disk I/O)
- ❌ NOT for storage-heavy workloads (only 10 GB)

### Choose Hostkey Italy If:
- ✅ Need **fast disk I/O** (databases, time-series)
- ✅ Need **good storage** (112 GB NVMe)
- ✅ **Budget constrained** (€4.17/month)
- ✅ Running **PostgreSQL, VictoriaMetrics, ClickHouse**
- ✅ Need **best performance-per-dollar** (paid tier)
- ✅ European location preferred

### Choose Hetzner If:
- ✅ Need **absolute fastest disk I/O** (1.4 GB/s write)
- ✅ Need **fastest network** (20 Gbps)
- ✅ Can use **ARM64 architecture**
- ✅ Premium performance is priority over cost
- ⚠️ Limited RAM (3.7 GB)
- ⚠️ Limited storage (38 GB)

### Choose Contabo If:
- ✅ Need **maximum storage** (150 GB)
- ✅ Storage-heavy workloads (backups, logs, media)
- ✅ Budget priority over performance
- ⚠️ Slowest disk I/O (SATA SSD)
- ⚠️ Slowest CPU

### Choose Oracle Cloud Free Tier If:
- ✅ Need **FREE hosting** ($0/month forever)
- ✅ Need **lots of RAM** (18 GB)
- ✅ Can use **ARM64 architecture**
- ✅ Asia region preferred (India)
- ⚠️ May have availability issues (free tier popular)
- ⚠️ Idle instances may be reclaimed

### For Uptrack/Truckex Infrastructure:

**Primary Services (PostgreSQL, VictoriaMetrics, Phoenix)**:
- 🥇 **Hostkey Italy** - Best balance of performance and cost
- 🥈 **Hetzner** - If budget allows and ARM64 works

**Secondary/Replica Services**:
- 🥇 **Oracle Free Tier** - FREE with excellent specs
- 🥈 **Contabo** - More storage for logs/backups

**Compute Workers (no database)**:
- 🥇 **GCP** - Fastest CPU (if budget allows)
- 🥈 **Hostkey** - Good CPU at lower cost

**NOT Recommended**:
- ❌ GCP for databases (disk I/O too slow)
- ❌ Contabo for primary database (disk I/O too slow)

---

## Immediate Action Required

### GCP Instance (34.130.208.111):

⚠️ **Disk 88% full - only 1.1 GB remaining!**

Options:
1. **Expand disk**: Increase from 10 GB to 20-50 GB
2. **Clean up**: Remove unused files, logs, Docker images
3. **Migrate**: Move to Hostkey for 112 GB storage at lower cost

```bash
# Check what's using space
sudo du -sh /* 2>/dev/null | sort -hr | head -20

# Clean Docker (if used)
docker system prune -af

# Clean apt cache
sudo apt-get clean
sudo apt-get autoremove -y

# Clean old logs
sudo journalctl --vacuum-time=3d
```

---

## Appendix: Raw Benchmark Commands

### CPU Benchmark
```bash
apt-get update && apt-get install -y sysbench
sysbench cpu --cpu-max-prime=20000 --threads=1 run
```

### Disk Write Benchmark
```bash
dd if=/dev/zero of=/tmp/testfile bs=1M count=1024 oflag=direct
```

### Disk Read Benchmark
```bash
dd if=/tmp/testfile of=/dev/null bs=1M count=1024 iflag=direct
```

### Network Speed Test
```bash
curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple
```

### System Information
```bash
lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core'
free -h
df -h /
cat /etc/os-release | head -5
```

---

**Report Generated**: 2025-12-02
**Benchmark Tool**: sysbench, dd, speedtest-cli
**Report Version**: 1.0
**Conclusion**: **Hostkey Italy remains the best choice for database workloads** 🏆
