-- 00-init-schemas.sql
-- Initialize the three schemas for multi-repo architecture
-- Run this on the primary Postgres node after Patroni bootstrap

-- Create schemas
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS oban;
CREATE SCHEMA IF NOT EXISTS results;

-- Create application user (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'uptrack') THEN
    CREATE USER uptrack WITH PASSWORD 'CHANGE_ME_IN_PRODUCTION';
  END IF;
END
$$;

-- Grant privileges
GRANT USAGE ON SCHEMA app TO uptrack;
GRANT USAGE ON SCHEMA oban TO uptrack;
GRANT USAGE ON SCHEMA results TO uptrack;

GRANT CREATE ON SCHEMA app TO uptrack;
GRANT CREATE ON SCHEMA oban TO uptrack;
GRANT CREATE ON SCHEMA results TO uptrack;

-- Grant all privileges on all tables (for migrations)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO uptrack;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA oban TO uptrack;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA results TO uptrack;

-- Grant all privileges on all sequences (for migrations)
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app TO uptrack;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA oban TO uptrack;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA results TO uptrack;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON TABLES TO uptrack;
ALTER DEFAULT PRIVILEGES IN SCHEMA oban GRANT ALL ON TABLES TO uptrack;
ALTER DEFAULT PRIVILEGES IN SCHEMA results GRANT ALL ON TABLES TO uptrack;

ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON SEQUENCES TO uptrack;
ALTER DEFAULT PRIVILEGES IN SCHEMA oban GRANT ALL ON SEQUENCES TO uptrack;
ALTER DEFAULT PRIVILEGES IN SCHEMA results GRANT ALL ON SEQUENCES TO uptrack;

-- Set search_path defaults (optional, can also be done per connection)
ALTER DATABASE uptrack_prod SET search_path TO public;

-- Create separate schema_migrations tables to avoid conflicts
CREATE TABLE IF NOT EXISTS app.app_schema_migrations (
  version bigint NOT NULL PRIMARY KEY,
  inserted_at timestamp(0) without time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS oban.oban_schema_migrations (
  version bigint NOT NULL PRIMARY KEY,
  inserted_at timestamp(0) without time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS results.results_schema_migrations (
  version bigint NOT NULL PRIMARY KEY,
  inserted_at timestamp(0) without time zone DEFAULT now()
);

-- Output confirmation
SELECT 'Schemas initialized successfully!' AS status;
SELECT schema_name FROM information_schema.schemata
WHERE schema_name IN ('app', 'oban', 'results')
ORDER BY schema_name;
