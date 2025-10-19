# Oracle Cloud Always Free Services - Uptrack Usage Analysis

**Date**: 2025-10-10
**Status**: Evaluation

---

## Summary: Which Services Should We Use?

| Service | Use It? | Why/Why Not |
|---------|---------|-------------|
| **Compute (ARM)** | ✅ **USING** | 4 cores, 24 GB RAM - our main Node A |
| **Block Volume** | ✅ **USE** | 200 GB extra storage for backups |
| **Object Storage** | ✅ **USE** | 20 GB for backups, exports, static files |
| **Email Delivery** | ✅ **USE** | Free alert emails instead of paid SMTP |
| **Notifications** | ✅ **USE** | 1M HTTPS webhooks/month for alerts |
| **Monitoring** | ✅ **USE** | 500M metrics/month - track all nodes |
| **Vault** | ✅ **USE** | Free secrets management |
| **Load Balancer** | ❌ **SKIP** | Can't balance across clouds (Netcup) |
| **Autonomous DB** | ❌ **SKIP** | Already using self-managed Postgres |
| **NoSQL Database** | 🤔 **MAYBE** | Could replace ClickHouse, but limited |

---

## ✅ Services We Should Use

### 1. **Block Volume Storage** (200 GB FREE)

**What it is**: Extra disk storage you can attach to your Oracle compute instance

**Current Setup**: Oracle instance has 200 GB boot volume

**How to use it**: Attach extra 200 GB for PostgreSQL backups

```bash
# Create block volume
oci bv volume create \
  --compartment-id <compartment-ocid> \
  --availability-domain <ad> \
  --display-name "postgres-backups" \
  --size-in-gbs 200

# Attach to instance
oci compute volume-attachment attach \
  --instance-id <instance-ocid> \
  --type iscsi \
  --volume-id <volume-ocid>

# Mount on instance
sudo mkfs.ext4 /dev/sdb
sudo mkdir /mnt/backups
sudo mount /dev/sdb /mnt/backups

# Setup automated PostgreSQL backups
sudo -u postgres pg_basebackup \
  -D /mnt/backups/pg_backup_$(date +%Y%m%d) \
  -Ft -z -P
```

**Benefit**: Free 200 GB for database backups (worth ~€4/month on other providers)

---

### 2. **Object Storage** (20 GB + 50k API requests/month FREE)

**What it is**: S3-compatible object storage (like AWS S3)

**How to use it**:
- Store PostgreSQL backups (compressed)
- Store monitor check exports (CSV/JSON)
- Store user-uploaded files (if you add that feature)
- Static assets/logs

```elixir
# Add to mix.exs
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.4"},
{:sweet_xml, "~> 0.7"}

# config/runtime.exs
config :ex_aws,
  region: "ap-mumbai-1",
  access_key_id: System.get_env("OCI_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("OCI_SECRET_ACCESS_KEY")

config :ex_aws, :s3,
  scheme: "https://",
  host: "objectstorage.ap-mumbai-1.oraclecloud.com",
  region: "ap-mumbai-1"
```

**Example usage in Uptrack**:

```elixir
# lib/uptrack/backup.ex
defmodule Uptrack.Backup do
  alias ExAws.S3

  def backup_postgres_to_s3 do
    backup_file = "/tmp/uptrack_backup_#{Date.utc_today()}.sql.gz"

    # Create backup
    System.cmd("pg_dump", [
      "-h", "100.64.0.1",
      "-U", "postgres",
      "-d", "uptrack_prod",
      "-f", backup_file,
      "-Z", "9"  # gzip compression
    ])

    # Upload to Oracle Object Storage
    backup_file
    |> S3.Upload.stream_file()
    |> S3.upload("uptrack-backups", "postgres/#{Path.basename(backup_file)}")
    |> ExAws.request()
  end

  def export_monitor_checks_to_s3(monitor_id, date_range) do
    # Export ClickHouse data to CSV
    csv_data = get_monitor_checks_csv(monitor_id, date_range)

    # Upload to S3
    S3.put_object("uptrack-exports", "checks/#{monitor_id}.csv", csv_data)
    |> ExAws.request()
  end
end

# Schedule daily backups in Oban
defmodule Uptrack.Workers.BackupWorker do
  use Oban.Worker, queue: :backups, max_attempts: 3

  @impl true
  def perform(_job) do
    Uptrack.Backup.backup_postgres_to_s3()
    :ok
  end
end
```

**Benefit**:
- Free 20 GB storage (worth €0.50-1/month)
- 50k API requests/month is plenty for backups
- S3-compatible, easy to migrate later if needed

---

### 3. **Email Delivery** (1M emails/month FREE)

**What it is**: SMTP service for sending emails

**Current Setup**: You probably use SendGrid, Mailgun, or similar ($15-20/month)

**How to use it**: Free alert emails for Uptrack incidents

```elixir
# Add to mix.exs
{:swoosh, "~> 1.16"},
{:gen_smtp, "~> 1.2"}

# config/runtime.exs
config :uptrack, Uptrack.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "smtp.us-ashburn-1.oraclecloud.com",
  port: 587,
  username: System.get_env("ORACLE_SMTP_USERNAME"),
  password: System.get_env("ORACLE_SMTP_PASSWORD"),
  tls: :always,
  auth: :always

# lib/uptrack/alerting/email.ex
defmodule Uptrack.Alerting.Email do
  import Swoosh.Email

  def incident_alert(user, incident, monitor) do
    new()
    |> to({user.name, user.email})
    |> from({"Uptrack Alerts", "alerts@uptrack.app"})
    |> subject("🚨 Monitor Down: #{monitor.name}")
    |> html_body("""
      <h2>Monitor is down</h2>
      <p><strong>Monitor:</strong> #{monitor.name}</p>
      <p><strong>URL:</strong> #{monitor.url}</p>
      <p><strong>Error:</strong> #{incident.cause}</p>
      <p><strong>Started at:</strong> #{incident.inserted_at}</p>
      <p><a href="https://uptrack.app/monitors/#{monitor.id}">View Details</a></p>
    """)
  end
end

# In your existing Alerting module
def send_incident_alerts(incident, monitor) do
  monitor
  |> get_alert_contacts()
  |> Enum.each(fn user ->
    user
    |> Uptrack.Alerting.Email.incident_alert(incident, monitor)
    |> Uptrack.Mailer.deliver()
  end)
end
```

**Setup in Oracle Cloud**:
1. Create SMTP credentials in Oracle Cloud Console
2. Verify sender email domain (uptrack.app)
3. Use SMTP endpoint: `smtp.us-ashburn-1.oraclecloud.com:587`

**Benefit**:
- Replace paid email service ($15-20/month savings)
- 1M emails/month = ~30k emails/day (plenty for monitoring alerts)
- No credit card needed

---

### 4. **Notifications Service** (1M HTTPS + 1k emails/month FREE)

**What it is**: Pub/Sub notification service for webhooks, SMS, email, Slack, PagerDuty

**How to use it**: Send alerts to Slack, Discord, PagerDuty, or custom webhooks

```elixir
# Add to mix.exs
{:oci, "~> 0.3"}

# lib/uptrack/alerting/oracle_notifications.ex
defmodule Uptrack.Alerting.OracleNotifications do

  @topic_ocid "ocid1.onstopic.oc1.ap-mumbai-1.xxxxx"

  def send_incident_to_slack(incident, monitor) do
    message = %{
      title: "🚨 Monitor Down: #{monitor.name}",
      url: monitor.url,
      error: incident.cause,
      timestamp: incident.inserted_at
    }

    # Oracle Notifications will forward to Slack webhook
    publish_message(@topic_ocid, Jason.encode!(message))
  end

  def send_to_pagerduty(incident, monitor) do
    # Similar - Oracle forwards to PagerDuty
    publish_message(@topic_ocid, build_pagerduty_payload(incident, monitor))
  end

  defp publish_message(topic_id, message) do
    # Use OCI SDK to publish
    OCI.ONS.publish_message(topic_id, message)
  end
end
```

**Setup**:
1. Create topic in Oracle Notifications
2. Add subscriptions:
   - HTTPS → Slack webhook
   - HTTPS → Discord webhook
   - HTTPS → PagerDuty
   - Email → your@email.com

**Benefit**:
- 1M HTTPS notifications/month (unlimited webhooks basically)
- Centralized notification routing
- Can replace Zapier/Make.com integrations

---

### 5. **Monitoring Service** (500M metrics/month FREE)

**What it is**: Metrics collection, alerting, dashboards (like Datadog/New Relic)

**How to use it**: Monitor all 3 nodes (Oracle + 2x Netcup) from one place

**Setup**:
```bash
# Install Oracle Cloud Agent on all 3 nodes
# (works even on Netcup via public API)

# On Oracle node (auto-installed)
# On Netcup nodes:
curl -L https://objectstorage.us-ashburn-1.oraclecloud.com/n/monitoring/b/release/o/unified-monitoring-agent/latest/linux/amd64/unified-monitoring-agent.deb -o /tmp/uma.deb
sudo dpkg -i /tmp/uma.deb

# Configure to send metrics to Oracle Cloud
# /etc/oracle-cloud-agent/uma.yaml
api_key: <your-oci-api-key>
region: ap-mumbai-1
namespace: uptrack_monitoring

metrics:
  - name: cpu_usage
    interval: 60s
  - name: memory_usage
    interval: 60s
  - name: disk_usage
    interval: 60s
  - name: postgres_connections
    command: psql -h 100.64.0.1 -U postgres -c "SELECT count(*) FROM pg_stat_activity"
  - name: clickhouse_queries
    command: clickhouse-client -q "SELECT value FROM system.metrics WHERE metric='Query'"
```

**Create Alarms**:
```
1. CPU > 80% for 5 minutes → Send notification
2. Memory > 90% for 5 minutes → Send notification
3. Disk > 85% → Send notification
4. Postgres down → Send notification
5. ClickHouse down → Send notification
```

**Benefit**:
- Replace Datadog/New Relic ($50-100/month savings)
- 500M metrics/month = ~200 metrics/minute (plenty!)
- Monitor all nodes (even Netcup) from Oracle dashboard

---

### 6. **Vault** (Unlimited software keys + 150 secrets FREE)

**What it is**: Secrets management (like HashiCorp Vault, AWS Secrets Manager)

**How to use it**: Store database passwords, API keys, encryption keys

**Currently you probably have**:
```bash
# /opt/uptrack/.env (BAD - plaintext on disk)
DATABASE_URL=postgresql://uptrack:PLAINTEXT_PASSWORD@100.64.0.1/uptrack_prod
SECRET_KEY_BASE=some_secret_key
CLICKHOUSE_PASSWORD=another_password
```

**With Oracle Vault**:
```elixir
# Add to mix.exs
{:oci, "~> 0.3"}

# lib/uptrack/secrets.ex
defmodule Uptrack.Secrets do
  @vault_id "ocid1.vault.oc1.ap-mumbai-1.xxxxx"

  def get_database_password do
    fetch_secret("database-password")
  end

  def get_secret_key_base do
    fetch_secret("phoenix-secret-key-base")
  end

  defp fetch_secret(secret_name) do
    case OCI.Secrets.get_secret_bundle(@vault_id, secret_name) do
      {:ok, %{data: %{content: encoded_content}}} ->
        Base.decode64!(encoded_content)

      {:error, reason} ->
        Logger.error("Failed to fetch secret: #{secret_name}")
        raise "Secret not found: #{reason}"
    end
  end
end

# config/runtime.exs
config :uptrack, Uptrack.Repo,
  url: build_database_url(),
  pool_size: 10

defp build_database_url do
  password = Uptrack.Secrets.get_database_password()
  "postgresql://uptrack:#{password}@100.64.0.1/uptrack_prod"
end
```

**Benefit**:
- Centralized secrets management
- Audit trail (who accessed what secret when)
- Automatic secret rotation
- No plaintext secrets on disk

---

## ❌ Services We Should SKIP

### 1. **Load Balancer** - Can't balance across clouds

**Problem**: Oracle Load Balancer can ONLY balance between Oracle instances in the same VCN.

Since we have:
- Node A: Oracle Mumbai
- Node B: Netcup Germany (different cloud)
- Node C: Netcup Germany (different cloud)

**Oracle LB cannot reach Netcup servers.**

**Solution**: Use Cloudflare DNS round-robin (already FREE and works great)

---

### 2. **Autonomous Database** - Overkill for our needs

**What it is**: Managed Oracle Database (2 free instances, 1 OCPU, 20 GB each)

**Why skip**:
- We're already using self-managed PostgreSQL with Patroni
- Autonomous DB is Oracle-specific (vendor lock-in)
- Only 20 GB storage (our Postgres will grow beyond this)
- 1 OCPU is weak (Patroni setup gives us 4 cores on Oracle + failover)
- Can't easily replicate to Netcup nodes

**Current setup is better**: PostgreSQL + Patroni gives us:
- 4 cores on Oracle (vs 1 OCPU Autonomous)
- 200 GB storage (vs 20 GB Autonomous)
- Replication to Netcup (Autonomous can't do this)
- Standard PostgreSQL (no vendor lock-in)

---

## 🤔 Services to EVALUATE

### **NoSQL Database** (133M reads/writes per month, 3 tables x 25 GB FREE)

**What it is**: Oracle's NoSQL database service

**Could it replace ClickHouse?**

**Current ClickHouse usage**:
- Stores monitor check results (time-series data)
- ~1,000 checks/day = 30k checks/month
- Each check = 1 write + occasional reads for dashboards

**NoSQL Database specs**:
- 133M reads/month = ~50 reads/second sustained
- 133M writes/month = ~50 writes/second sustained
- 3 tables x 25 GB = 75 GB total

**Comparison**:

| Feature | ClickHouse (Self-hosted) | Oracle NoSQL (Free) |
|---------|-------------------------|---------------------|
| Cost | Runs on Netcup (included) | FREE |
| Writes/month | ~30k (well within limits) | 133M limit (4400x headroom) |
| Storage | Can use all 100 GB on Netcup | 75 GB free (plenty) |
| Query language | SQL-like | JSON/REST API |
| Performance | Optimized for time-series | General purpose NoSQL |
| Replication | Manual setup | Built-in (3 copies) |
| Location | Netcup Germany | Oracle Mumbai |

**Verdict**:
- ✅ **Technically viable** - NoSQL limits are plenty for Uptrack
- ⚠️ **BUT** - ClickHouse is better optimized for time-series analytics
- ⚠️ **Migration effort** - Would need to rewrite queries from SQL to NoSQL
- ⚠️ **Latency** - NoSQL in Mumbai only, ClickHouse replica in EU is faster for EU users

**Recommendation**: **Stick with ClickHouse** unless you want to save the €5.26/month Netcup Node C costs. The migration effort isn't worth it for a production app.

---

## 📊 Summary: Services to Implement

### Immediate wins (implement these now):

1. ✅ **Email Delivery** - Replace paid SMTP (saves €15-20/month)
2. ✅ **Notifications** - Free Slack/Discord/PagerDuty webhooks
3. ✅ **Object Storage** - Free backups and exports (saves €1-2/month)

### Nice to have (implement when you have time):

4. ✅ **Block Volume** - Extra 200 GB for backups (saves €4/month)
5. ✅ **Monitoring** - Centralized metrics for all nodes (saves €50-100/month)
6. ✅ **Vault** - Better secrets management (security improvement)

### Total potential savings:
- Email: €15-20/month
- Monitoring: €50-100/month
- Storage: €5-6/month
- **Total: €70-126/month savings** 🎉

---

## 🚀 Implementation Priority

**Phase 1 (This week)**:
- Set up Email Delivery for alert emails
- Configure Notifications for Slack webhooks

**Phase 2 (Next week)**:
- Set up Object Storage for backups
- Attach Block Volume for PostgreSQL backups

**Phase 3 (When needed)**:
- Implement Monitoring service
- Migrate secrets to Vault

**Total setup time**: ~4-6 hours
**Total savings**: €70-126/month

---

## 📚 Resources

- [Oracle Cloud Always Free Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Email Delivery Setup](https://docs.oracle.com/en-us/iaas/Content/Email/home.htm)
- [Object Storage Setup](https://docs.oracle.com/en-us/iaas/Content/Object/home.htm)
- [Notifications Service](https://docs.oracle.com/en-us/iaas/Content/Notification/home.htm)
- [Monitoring Service](https://docs.oracle.com/en-us/iaas/Content/Monitoring/home.htm)
- [Vault Service](https://docs.oracle.com/en-us/iaas/Content/KeyManagement/home.htm)
