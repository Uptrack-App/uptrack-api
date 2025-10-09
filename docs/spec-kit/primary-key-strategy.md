# Primary Key Strategy Specification

## Overview

This document defines the primary key strategy for Uptrack's database tables, balancing performance requirements with distributed system needs. We use **UUID version 7** for globally unique identifiers, which provides time-ordered, sortable UUIDs ideal for distributed systems.

## Strategy

### UUID Primary Keys

Use UUIDs for tables that benefit from global uniqueness and external system integration:

- **`users`** - Integration with external authentication systems (GitHub, Google OAuth)
- **`monitors`** - Supports future distributed monitoring architecture
- **`incidents`** - External API references and public incident IDs
- **`status_pages`** - Public-facing resources that may be referenced externally
- **`alert_channels`** - Integration with external notification services

### Integer Primary Keys

Keep integers for performance-critical and high-volume tables:

- **`monitor_checks`** - High volume, performance critical for time-series operations
- **Join tables** (`status_page_monitors`) - Unnecessary overhead for internal references
- **`incident_updates`** - High frequency writes, internal-only references

## Rationale

### Why UUID v7 for Core Business Entities

1. **Global Uniqueness**: Prevents ID collisions when integrating multiple systems
2. **Time-Ordered**: UUID v7 includes timestamp prefix, providing natural sorting order
3. **Database Optimized**: Better for database performance compared to random UUIDs (v4)
4. **Security**: Non-sequential IDs prevent enumeration attacks
5. **Distribution Ready**: Supports future multi-region deployments
6. **External APIs**: Safe to expose in public APIs without revealing system scale

### Why Integers for High-Volume Tables

1. **Performance**: Smaller index size (8 bytes vs 16 bytes)
2. **Join Performance**: Faster foreign key operations
3. **Storage Efficiency**: Critical for time-series data (`monitor_checks`)
4. **Database Optimization**: Better query planner performance for large datasets

## Implementation Notes

- Use `Uniq.UUID` with `version: 7` for UUID v7 primary keys
- Configure schemas with `@primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}`
- Foreign keys from integer tables to UUID tables use `Uniq.UUID` type
- Database migrations use `:uuid` type for UUID v7 columns
- The `uniq` library provides UUID v7 generation via `Uniq.UUID.uuid7/0`
- Consider compound indexes when UUID foreign keys are frequently queried

## Migration Strategy

1. New tables follow this specification from creation
2. Existing tables can be migrated individually based on priority
3. High-volume tables (`monitor_checks`) remain integer-based permanently

## Examples

### Schema Configuration

```elixir
# UUID v7 table schema
defmodule Uptrack.Monitoring.Monitor do
  use Ecto.Schema

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID

  schema "monitors" do
    field :name, :string
    # ...
  end
end

# Integer table with UUID v7 foreign key
defmodule Uptrack.Monitoring.MonitorCheck do
  use Ecto.Schema

  @foreign_key_type Uniq.UUID

  schema "monitor_checks" do
    field :status, :string
    belongs_to :monitor, Monitor
    # ...
  end
end
```

### Migration Examples

```elixir
# UUID v7 table
create table("app.monitors", primary_key: false) do
  add :id, :uuid, primary_key: true
  add :name, :string, null: false
  # ...
end

# Integer table with UUID v7 foreign key
create table("app.monitor_checks") do
  add :status, :string, null: false
  add :monitor_id, references("app.monitors", type: :uuid), null: false
  # ...
end
```