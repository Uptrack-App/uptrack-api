# App Schema Migration (app schema)

```sql
-- Create app schema
CREATE SCHEMA IF NOT EXISTS app;

-- Accounts table
CREATE TABLE app.accounts (
    id bigserial PRIMARY KEY,
    plan text NOT NULL,
    status text NOT NULL,
    inserted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Monitors table
CREATE TABLE app.monitors (
    id bigserial PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES app.accounts(id),
    url text NOT NULL,
    interval_s integer NOT NULL,
    active boolean NOT NULL DEFAULT true,
    inserted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Useful index
CREATE INDEX idx_monitors_account_active ON app.monitors(account_id, active);
```
