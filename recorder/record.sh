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
AUDIO_DEVICE="${AUDIO_DEVICE:-hw:2,0}"
SOX_TIMEOUT_MARGIN="${SOX_TIMEOUT_MARGIN:-120}"
SPECTROGRAM_TIMEOUT="${SPECTROGRAM_TIMEOUT:-300}"

# --- Cargar config externa si existe ---
CONFIG_FILE="${DATA_DIR}/config.txt"
if [ -f "$CONFIG_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      STATION) STATION="$value" ;;
      BITRATE) BITRATE="$value" ;;
      SAMPLE_RATE) SAMPLE_RATE="$value" ;;
      GAIN) GAIN="$value" ;;
      DURATION) DURATION="$value" ;;
      IDRECORDER) IDRECORDER="$value" ;;
      SLEEPDURATION) SLEEPDURATION="$value" ;;
      GPIO_PIN) GPIO_PIN="$value" ;;
      AUDIO_DEVICE) AUDIO_DEVICE="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

# --- Rutas dentro del contenedor ---
RECORDINGS_DIR="$DATA_DIR/recordings"
BACKUP_DIR="$DATA_DIR/sdBackup"
STATS_FILE="$DATA_DIR/stats.txt"
LOG_FILE="$DATA_DIR/${STATION}opi.log"
STATE_FILE="$DATA_DIR/recorder_state.env"
SPECTROGRAM_BIN="/app/spectrogram/spectrogram"

mkdir -p "$RECORDINGS_DIR" "$BACKUP_DIR"
touch "$STATS_FILE" "$LOG_FILE" "$STATE_FILE"

write_state() {
  key="$1"
  value="$2"
  tmp="${STATE_FILE}.tmp"
  if [ -f "$STATE_FILE" ]; then
    grep -v "^${key}=" "$STATE_FILE" > "$tmp" || true
  else
    : > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

write_state RECORDER_PID "$$"
write_state LAST_START_TS "$(date +%s)"
write_state LAST_STAGE "init"
write_state LAST_ERROR "none"

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
  SOX_TIMEOUT=$((DURATION + SOX_TIMEOUT_MARGIN))

  write_state LAST_STAGE "recording"
  write_state LAST_RECORDING_START_TS "$(date +%s)"
  write_state CURRENT_WAV "$WAV_PATH"
  write_state LAST_ERROR "none"

  # Grabacion. timeout evita que sox quede colgado indefinidamente.
  timeout --kill-after=10s "${SOX_TIMEOUT}s" \
    sox -t alsa "$AUDIO_DEVICE" -r "$SAMPLE_RATE" -b "$BITRATE" -c 1 "$WAV_PATH" trim 0 "$DURATION"

  write_state LAST_WAV "$WAV_PATH"
  write_state LAST_WAV_TS "$(date +%s)"
  write_state LAST_STAGE "spectrogram"

  mkdir -p "$BACKUP_DIR/$DIRECTORY"

  # Spectrograma. Si falla o se cuelga, el contenedor sale y Docker lo reinicia.
  if [ -x "$SPECTROGRAM_BIN" ]; then
    set +e
    timeout --kill-after=10s "${SPECTROGRAM_TIMEOUT}s" "$SPECTROGRAM_BIN" "$WAV_PATH"
    code="$?"
    set -e
    if [ "$code" -ne 0 ]; then
      write_state LAST_ERROR "spectrogram_failed_exit_${code}"
      write_state LAST_SPECTROGRAM_STATUS "failed"
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR spectrogram failed exit=${code} file=${WAV_PATH}" >> "$LOG_FILE"
      exit 1
    fi
    write_state LAST_SPECTROGRAM_STATUS "ok"
    write_state LAST_SPECTROGRAM_TS "$(date +%s)"
  else
    write_state LAST_SPECTROGRAM_STATUS "missing"
  fi

  # Temperatura placa, solo para log de grabacion
  BOARD_TEMP=""
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW="$(cat /sys/class/thermal/thermal_zone0/temp)"
    BOARD_TEMP="$(awk '{printf("%d",$1/1000)}' <<<"${TEMP_RAW}")"
  fi

  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE ${STATION}${SAFE_FILE}.wav" >> "$LOG_FILE"
  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE ${STATION}${SAFE_FILE}.wav" >> "$STATS_FILE"

  write_state LAST_STATS_TS "$(date +%s)"
  write_state LAST_STAGE "sleeping"

  # Si quieres mover a backup:
  # mv "$WAV_PATH"* "$BACKUP_DIR/$DIRECTORY/" || true

  sleep "$SLEEPDURATION"
done
