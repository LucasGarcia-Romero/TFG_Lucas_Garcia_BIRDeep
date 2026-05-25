#!/bin/bash
set -euo pipefail

# --- ENV desde docker-compose ---
DATA_DIR="${DATA_DIR:-/data}"
STATION="${STATION:-TECHOUTAD_}"
BITRATE="${BITRATE:-16}"
SAMPLE_RATE="${SAMPLE_RATE:-32000}"
GAIN="${GAIN:-5.0}"
DURATION="${DURATION:-60}"
IDRECORDER="${IDRECORDER:-1}"
SLEEPDURATION="${SLEEPDURATION:-10}"
GPIO_PIN="${GPIO_PIN:-117}"

# --- Cargar config externa si existe ---
CONFIG_FILE="${DATA_DIR}/config.txt"
if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            STATION)       STATION="$value" ;;
            BITRATE)       BITRATE="$value" ;;
            SAMPLE_RATE)   SAMPLE_RATE="$value" ;;
            GAIN)          GAIN="$value" ;;
            DURATION)      DURATION="$value" ;;
            IDRECORDER)    IDRECORDER="$value" ;;
            SLEEPDURATION) SLEEPDURATION="$value" ;;
            GPIO_PIN)      GPIO_PIN="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# --- Rutas dentro del contenedor ---
RECORDINGS_DIR="$DATA_DIR/recordings"
BACKUP_DIR="$DATA_DIR/sdBackup"
STATS_FILE="$DATA_DIR/stats.txt"
LOG_FILE="$DATA_DIR/${STATION}opi.log"

SPECTROGRAM_BIN="/app/spectrogram/spectrogram"

mkdir -p "$RECORDINGS_DIR" "$BACKUP_DIR"
touch "$STATS_FILE" "$LOG_FILE"

# --- GPIO (si existe /sys y hay permisos) ---
if [ -d /sys/class/gpio ]; then
  if [ ! -e "/sys/class/gpio/gpio${GPIO_PIN}" ]; then
    echo "$GPIO_PIN" > /sys/class/gpio/export 2>/dev/null || true
  fi
  echo out > "/sys/class/gpio/gpio${GPIO_PIN}/direction" 2>/dev/null || true
  echo 1 > "/sys/class/gpio/gpio${GPIO_PIN}/value" 2>/dev/null || true
fi

while true; do
  FILE_DATE="$(date +"%Y-%m-%d %T")"
  DIRECTORY="$(date +"%Y-%m-%d")"

  SAFE_FILE="${FILE_DATE//:/_}"
  SAFE_FILE="${SAFE_FILE// /_}"

  WAV_PATH="$RECORDINGS_DIR/${STATION}${SAFE_FILE}.wav"

  # Grabación
  sox -t alsa hw:1 -r "$SAMPLE_RATE" -b "$BITRATE" -c 1 "$WAV_PATH" trim 0 "$DURATION" 2>/dev/null

  mkdir -p "$BACKUP_DIR/$DIRECTORY"

  # Spectrograma
  if [ -x "$SPECTROGRAM_BIN" ]; then
    "$SPECTROGRAM_BIN" "$WAV_PATH" || true
  fi

  # Temperatura placa, solo para log de grabación
  BOARD_TEMP=""
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW="$(cat /sys/class/thermal/thermal_zone0/temp)"
    BOARD_TEMP="$(awk '{printf("%d",$1/1000)}' <<<"${TEMP_RAW}")"
  fi

  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE ${STATION}${SAFE_FILE}.wav" >> "$LOG_FILE"
  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE ${STATION}${SAFE_FILE}.wav" >> "$STATS_FILE"

  # Si quieres mover a backup:
  # mv "$WAV_PATH"* "$BACKUP_DIR/$DIRECTORY/" || true

  sleep "$SLEEPDURATION"
done