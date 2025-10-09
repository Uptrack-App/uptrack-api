#!/usr/bin/env bash
# clickhouse-flush-spool.sh
# Flushes spooled ClickHouse writes from disk
# Deploy to: /usr/local/bin/clickhouse-flush-spool.sh

set -euo pipefail

SPOOL_DIR="${SPOOL_DIR:-/var/lib/uptrack/spool}"
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-100.C.C.C}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
LOG_PREFIX="[clickhouse-flush-spool]"

# Check if spool directory exists
if [[ ! -d "$SPOOL_DIR" ]]; then
  echo "$LOG_PREFIX Spool directory $SPOOL_DIR does not exist, creating..."
  mkdir -p "$SPOOL_DIR"
  chown uptrack:uptrack "$SPOOL_DIR"
  exit 0
fi

# Count pending files
PENDING_COUNT=$(find "$SPOOL_DIR" -name "*.sql" -type f 2>/dev/null | wc -l)

if [[ $PENDING_COUNT -eq 0 ]]; then
  echo "$LOG_PREFIX No spooled files to flush"
  exit 0
fi

echo "$LOG_PREFIX Found $PENDING_COUNT spooled file(s), flushing..."

SUCCESS_COUNT=0
FAIL_COUNT=0

# Process each .sql file
while IFS= read -r -d '' file; do
  FILENAME=$(basename "$file")
  echo "$LOG_PREFIX Processing $FILENAME..."

  # Attempt to insert into ClickHouse
  if clickhouse-client \
    --host="$CLICKHOUSE_HOST" \
    --port="$CLICKHOUSE_PORT" \
    --multiquery \
    --query="$(cat "$file")" 2>&1 | tee -a /var/log/uptrack/clickhouse-flush.log; then

    echo "$LOG_PREFIX Successfully flushed $FILENAME"
    rm -f "$file"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "$LOG_PREFIX Failed to flush $FILENAME, will retry later" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done < <(find "$SPOOL_DIR" -name "*.sql" -type f -print0)

echo "$LOG_PREFIX Flush complete: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed"

exit 0
