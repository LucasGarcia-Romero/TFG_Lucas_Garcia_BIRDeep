#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RECORDINGS_DIR="$DATA_DIR/recordings"
BACKUP_DIR="$DATA_DIR/sdBackup"
STATS_FILE="$DATA_DIR/stats.txt"

mkdir -p "$RECORDINGS_DIR" "$BACKUP_DIR"
touch "$STATS_FILE"
 
exec /app/record.sh