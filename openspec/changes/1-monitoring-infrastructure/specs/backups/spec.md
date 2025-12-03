# Capability: infrastructure/backups

Backup and disaster recovery using WAL-G for PostgreSQL and vmbackup for VictoriaMetrics, both targeting Backblaze B2.

## ADDED Requirements

### Requirement: PostgreSQL Backup with WAL-G to Backblaze B2
The system SHALL use WAL-G to continuously archive PostgreSQL WAL files to b2://uptrack/pg/wal/ and SHALL perform daily base backups to b2://uptrack/pg/base/.

**ID:** infra-backup-001
**Priority:** Critical

WAL-G provides point-in-time recovery with RPO <1 minute vs daily dumps (RPO: 24 hours). Continuous WAL archiving enables PITR.

#### Scenario: Continuous WAL archiving to B2
**Given** PostgreSQL primary is writing transactions
**When** a WAL segment (16MB) fills up
**Then** WAL-G archives WAL to b2://uptrack/pg/wal/
**And** WAL transfer completes within 30 seconds

#### Scenario: Point-in-time recovery from B2
**Given** a corruption occurred at 14:35 UTC yesterday
**When** operator restores base backup from 02:00 UTC and applies WAL files up to 14:34 UTC using WAL-G
**Then** database is restored to 14:34 UTC
**And** only 1 minute of data is lost (RPO: <1 minute)

#### Scenario: Daily base backup to B2
**Given** PostgreSQL primary is operational
**When** WAL-G backup cron runs daily at 02:00 UTC
**Then** wal-g backup-push uploads base backup to b2://uptrack/pg/base/
**And** backup completes within 30 minutes
**And** backup is incremental

---

### Requirement: VictoriaMetrics Backup Strategy
The system SHALL perform daily VictoriaMetrics backups to b2://uptrack/vm/ using vmbackup, and backups SHALL be retained per policy: PostgreSQL 30 days, VictoriaMetrics 30 days.

**ID:** infra-backup-002
**Priority:** High

Daily backups provide RPO of 1 day vs 7 days with weekly backups. For paid monitoring service, losing 1 week of historical uptime data is unacceptable for SLA reporting and customer analytics. Cost increase ($0.75/mo) is justified by 7x better RPO.

#### Scenario: Daily vmbackup to B2
**Given** vmstorage on eu-a has 15 months of metrics
**When** daily backup cron runs at 03:00 UTC
**Then** vmbackup exports data to b2://uptrack/vm/eu-a/
**And** backup is incremental
**And** first backup takes ~30 minutes, subsequent <10 minutes

#### Scenario: PostgreSQL backup retention
**Given** WAL-G has backed up for 60 days
**When** retention cleanup runs
**Then** base backups older than 30 days are deleted
**And** B2 storage for PG remains <200GB (~$1/month)

#### Scenario: VictoriaMetrics backup retention
**Given** vmbackup has run for 45 days
**When** retention cleanup runs
**Then** backups older than 30 days are deleted
**And** B2 storage for VM remains <200GB (~$1.50/month)

---

### Requirement: Backup Operations and Recovery
The system SHALL verify backup integrity monthly, B2 credentials SHALL be stored encrypted, the system SHALL alert if backups fail, and documentation SHALL include disaster recovery runbooks.

**ID:** infra-backup-003
**Priority:** High

Untested backups are useless. Silent failures lead to data loss. DR procedures enable fast recovery during disasters.

#### Scenario: Monthly PostgreSQL restore test
**Given** it is the 1st of the month
**When** automated restore test runs
**Then** WAL-G restores from B2 to test instance
**And** test queries validate data integrity
**And** test instance is destroyed after validation

#### Scenario: B2 credentials encryption
**Given** WAL-G and vmbackup need B2 access
**When** checking configuration files
**Then** B2 credentials are stored via agenix or sops-nix (encrypted)
**And** no plain text credentials in git repository

#### Scenario: Alert on backup failure
**Given** PostgreSQL WAL-G backup is scheduled daily at 02:00 UTC
**When** backup fails
**Then** alert fires within 5 minutes with error message

#### Scenario: DR runbook for complete EU loss
**Given** all EU nodes are destroyed
**When** operator opens DR runbook
**Then** runbook provides steps to promote india-s, restore VM from B2, update DNS
**And** runbook includes expected RTO: 4 hours, RPO: 1-2 seconds (PG), 1 day (VM)
