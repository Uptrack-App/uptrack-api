# Oban Schema Migration (oban schema)

```sql
-- Create oban schema
CREATE SCHEMA IF NOT EXISTS oban;

-- Run Oban migrations into this schema
-- (if using Oban mix tasks, pass `prefix: "oban"`)

-- Example: base jobs table (Oban.Migrations.up will create this and more)
CREATE TABLE oban.jobs (
    id bigserial PRIMARY KEY,
    queue text NOT NULL,
    state text NOT NULL,
    worker text NOT NULL,
    args jsonb NOT NULL,
    errors jsonb[] NOT NULL DEFAULT '{}',
    attempt int NOT NULL DEFAULT 0,
    max_attempts int NOT NULL DEFAULT 20,
    inserted_at timestamptz NOT NULL DEFAULT now(),
    scheduled_at timestamptz NOT NULL DEFAULT now()
);

-- Add required Oban indexes
CREATE INDEX oban_jobs_queue_state ON oban.jobs(queue, state);
CREATE INDEX oban_jobs_scheduled_at ON oban.jobs(scheduled_at);
```
