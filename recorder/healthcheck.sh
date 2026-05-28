#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RECORDINGS_DIR="$DATA_DIR/recordings"
STATS_FILE="$DATA_DIR/stats.txt"
DURATION="${DURATION:-60}"
SLEEPDURATION="${SLEEPDURATION:-10}"
MARGIN="${WATCHDOG_MARGIN_SECONDS:-600}"
SAMPLE_RATE="${SAMPLE_RATE:-32000}"
BITRATE="${BITRATE:-16}"
CHANNELS="${CHANNELS:-1}"
MIN_RATIO="${WATCHDOG_MIN_VALID_WAV_RATIO_PERCENT:-5}"
DISK_MAX="${WATCHDOG_DISK_MAX_USED_PERCENT:-95}"
EMPTY_LIMIT="${WATCHDOG_EMPTY_WAV_CONSECUTIVE_LIMIT:-5}"

CONFIG_FILE="$DATA_DIR/config.txt"
if [ -f "$CONFIG_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      DURATION) DURATION="$value" ;;
      SLEEPDURATION) SLEEPDURATION="$value" ;;
      SAMPLE_RATE) SAMPLE_RATE="$value" ;;
      BITRATE) BITRATE="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

now="$(date +%s)"
timeout=$((DURATION + SLEEPDURATION + MARGIN))
min_bytes=$((SAMPLE_RATE * CHANNELS * BITRATE / 8 * DURATION * MIN_RATIO / 100))
sox_timeout=$((DURATION + 120))
spectrogram_timeout=300

fail() {
  echo "UNHEALTHY: $*" >&2
  exit 1
}

[ -d "$RECORDINGS_DIR" ] || fail "$RECORDINGS_DIR no existe"
[ -w "$DATA_DIR" ] || fail "$DATA_DIR no es escribible"

used_percent="$(df -P "$DATA_DIR" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
if [ -n "$used_percent" ] && [ "$used_percent" -ge "$DISK_MAX" ]; then
  fail "disco casi lleno: ${used_percent}% >= ${DISK_MAX}%"
fi

latest_wav="$(find "$RECORDINGS_DIR" -maxdepth 1 -type f -name '*.wav' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"
if [ -z "$latest_wav" ]; then
  # Durante el arranque puede no existir ningun WAV todavia. Docker start_period cubre el caso normal.
  fail "no hay archivos WAV"
fi

latest_mtime="$(stat -c %Y "$latest_wav")"
age=$((now - latest_mtime))
if [ "$age" -gt "$timeout" ]; then
  fail "no hay WAV nuevo desde hace ${age}s; umbral ${timeout}s"
fi

stats_age=0
if [ ! -f "$STATS_FILE" ]; then
  fail "$STATS_FILE no existe"
else
  stats_mtime="$(stat -c %Y "$STATS_FILE")"
  stats_age=$((now - stats_mtime))
  if [ "$stats_age" -gt "$timeout" ]; then
    fail "stats.txt no se actualiza desde hace ${stats_age}s; umbral ${timeout}s"
  fi
fi

mapfile -t last_wavs < <(find "$RECORDINGS_DIR" -maxdepth 1 -type f -name '*.wav' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR<=5 {print $2}')
if [ "${#last_wavs[@]}" -ge "$EMPTY_LIMIT" ]; then
  small_count=0
  for wav in "${last_wavs[@]}"; do
    size="$(stat -c %s "$wav" 2>/dev/null || echo 0)"
    if [ "$size" -lt "$min_bytes" ]; then
      small_count=$((small_count + 1))
    fi
  done
  if [ "$small_count" -ge "$EMPTY_LIMIT" ]; then
    fail "${small_count} WAV consecutivos demasiado pequenos; umbral ${min_bytes} bytes"
  fi
fi

# Detecta procesos colgados dentro del contenedor.
# Requiere procps, incluido en recorder/Dockerfile.
if pgrep -x sox >/dev/null 2>&1; then
  while read -r etimes comm args; do
    if [ "${etimes:-0}" -gt "$sox_timeout" ]; then
      fail "sox lleva ${etimes}s vivo; umbral ${sox_timeout}s"
    fi
  done < <(ps -eo etimes=,comm=,args= | awk '$2=="sox" {print}')
fi

if pgrep -f '/app/spectrogram/spectrogram' >/dev/null 2>&1; then
  while read -r etimes comm args; do
    if [ "${etimes:-0}" -gt "$spectrogram_timeout" ]; then
      fail "spectrogram lleva ${etimes}s vivo; umbral ${spectrogram_timeout}s"
    fi
  done < <(ps -eo etimes=,comm=,args= | grep '/app/spectrogram/spectrogram' | grep -v grep || true)
fi

echo "OK: latest_wav=$(basename "$latest_wav") age=${age}s stats_age=${stats_age}s min_bytes=${min_bytes} disk=${used_percent}%"
exit 0
