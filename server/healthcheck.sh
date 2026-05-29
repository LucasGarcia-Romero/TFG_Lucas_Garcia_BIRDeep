#!/usr/bin/env bash
set -euo pipefail

URL="${SERVER_HEALTH_URL:-http://localhost:8000/}"

if command -v wget >/dev/null 2>&1; then
  wget -q --spider "$URL"
elif command -v curl >/dev/null 2>&1; then
  curl -fsS "$URL" >/dev/null
else
  echo "No wget or curl available"
  exit 1
fi
