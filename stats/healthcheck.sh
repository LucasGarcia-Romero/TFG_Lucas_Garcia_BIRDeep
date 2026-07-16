#!/usr/bin/env bash
set -euo pipefail
 
DATA_DIR="${DATA_DIR:-/data}"
HISTORY_FILE="${HISTORY_FILE:-$DATA_DIR/sensor_history.csv}"
MAX_AGE_SECONDS="${STATS_MAX_AGE_SECONDS:-300}"

test -d "$DATA_DIR"
test -w "$DATA_DIR"

if [ -f "$HISTORY_FILE" ]; then
  file="$HISTORY_FILE"
else
  echo "No stats file found: $HISTORY_FILE"
  exit 1
fi

now="$(date +%s)"
mtime="$(stat -c %Y "$file")"
age=$((now - mtime))

if [ "$age" -gt "$MAX_AGE_SECONDS" ]; then
  echo "Stats file too old: ${file}, age=${age}s, max=${MAX_AGE_SECONDS}s"
  exit 1
fi

exit 0
