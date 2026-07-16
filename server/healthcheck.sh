#!/usr/bin/env bash
set -euo pipefail

URL="${SERVER_HEALTH_URL:-http://127.0.0.1:8000/}"

if command -v wget >/dev/null 2>&1; then
  wget -q -O /dev/null -T 5 "$URL"
elif command -v curl >/dev/null 2>&1; then
  curl -fsS --connect-timeout 2 --max-time 5 "$URL" >/dev/null
else
  echo "No wget or curl available"
  exit 1
fi