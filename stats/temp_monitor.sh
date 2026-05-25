#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-10}"
MAX_LINES="${MAX_LINES:-8640}"  # 24h si SLEEP_INTERVAL=10s

SENSOR_FILE="${DATA_DIR}/sensor_history.csv"
CPU_TEMP_FILE="${DATA_DIR}/cpu_temp.txt"       # compatibilidad con el histórico antiguo
DHT22_BIN="${DHT22_BIN:-/app/DHT22/dht22.out}"

mkdir -p "$DATA_DIR"

if [ ! -f "$SENSOR_FILE" ]; then
  echo "timestamp,internal_temp,external_temp,humidity" > "$SENSOR_FILE"
fi

touch "$CPU_TEMP_FILE"

read_internal_temp() {
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp
  fi
}

read_dht22() {
  if [ ! -x "$DHT22_BIN" ]; then
    return 0
  fi

  local output sensor_line
  output="$($DHT22_BIN 2>/dev/null || true)"

  # El binario puede imprimir líneas de debug tipo "0x..." antes de la línea real.
  # Nos quedamos con la última línea cuyo primer y segundo campo sean numéricos.
  sensor_line="$(printf '%s\n' "$output" | awk '
    NF >= 2 && $1 ~ /^-?[0-9]+([.][0-9]+)?$/ && $2 ~ /^-?[0-9]+([.][0-9]+)?$/ { temp=$1; hum=$2 }
    END { if (temp != "" || hum != "") print temp, hum }
  ')"

  if [ -n "$sensor_line" ]; then
    printf '%s\n' "$sensor_line"
  fi
}

rotate_csv() {
  local file="$1"
  local line_count tmp
  line_count="$(wc -l < "$file")"
  if [ "$line_count" -gt "$((MAX_LINES + 101))" ]; then
    tmp="$(mktemp)"
    head -n 1 "$file" > "$tmp"
    tail -n "$MAX_LINES" "$file" >> "$tmp"
    mv "$tmp" "$file"
  fi
}

rotate_plain() {
  local file="$1"
  local line_count tmp
  line_count="$(wc -l < "$file")"
  if [ "$line_count" -gt "$((MAX_LINES + 100))" ]; then
    tmp="$(mktemp)"
    tail -n "$MAX_LINES" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
}

while true; do
  TIMESTAMP="$(date '+%Y-%m-%d %T')"
  INTERNAL_TEMP="$(read_internal_temp || true)"

  EXTERNAL_TEMP=""
  HUMIDITY=""
  DHT_LINE="$(read_dht22 || true)"
  if [ -n "$DHT_LINE" ]; then
    read -r EXTERNAL_TEMP HUMIDITY _ <<< "$DHT_LINE" || true
  fi

  echo "${TIMESTAMP},${INTERNAL_TEMP},${EXTERNAL_TEMP},${HUMIDITY}" >> "$SENSOR_FILE"

  # Archivo antiguo, por si alguna pantalla o script anterior todavía lo usa.
  if [ -n "$INTERNAL_TEMP" ]; then
    echo "${TIMESTAMP} BOARD_TEMP=${INTERNAL_TEMP}C" >> "$CPU_TEMP_FILE"
  fi

  rotate_csv "$SENSOR_FILE"
  rotate_plain "$CPU_TEMP_FILE"

  sleep "$SLEEP_INTERVAL"
done
