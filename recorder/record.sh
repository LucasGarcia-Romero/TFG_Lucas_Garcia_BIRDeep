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
PROGRAMS_DIR="/home/orangepi"

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

echo "============================================================"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] Servicio iniciado"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] DATA_DIR: $DATA_DIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] RECORDINGS_DIR: $RECORDINGS_DIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] STATION: $STATION"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] AUDIO_DEVICE: $AUDIO_DEVICE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] SAMPLE_RATE: $SAMPLE_RATE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] BITRATE: $BITRATE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] DURATION: $DURATION"
echo "============================================================"

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

  WAV_NAME="${STATION}${SAFE_FILE}.wav"
  WAV_PATH="$RECORDINGS_DIR/$WAV_NAME"

  SOX_TIMEOUT=$((DURATION + SOX_TIMEOUT_MARGIN))

  write_state LAST_STAGE "recording"
  write_state LAST_RECORDING_START_TS "$(date +%s)"
  write_state CURRENT_WAV "$WAV_PATH"
  write_state LAST_ERROR "none"

  echo
  echo "------------------------------------------------------------"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Iniciando grabación"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Nombre del audio: $WAV_NAME"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Ruta del audio: $WAV_PATH"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Dispositivo: $AUDIO_DEVICE"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Duración: ${DURATION}s"
  echo "------------------------------------------------------------"

  # Grabación. timeout evita que SoX quede colgado indefinidamente.
  timeout --kill-after=10s "${SOX_TIMEOUT}s" \
    sox \
      -t alsa "$AUDIO_DEVICE" \
      -r "$SAMPLE_RATE" \
      -b "$BITRATE" \
      -c 1 \
      "$WAV_PATH" \
      trim 0 "$DURATION"

  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Grabación finalizada"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Audio creado: $WAV_NAME"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Ruta creada: $WAV_PATH"

  if [ ! -f "$WAV_PATH" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] ERROR: no existe el audio $WAV_PATH" >&2

    write_state LAST_ERROR "wav_not_created"
    write_state LAST_STAGE "error"

    exit 1
  fi

  WAV_SIZE_BYTES="$(stat -c '%s' "$WAV_PATH")"
  WAV_SIZE_HUMAN="$(du -h "$WAV_PATH" | cut -f1)"

  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Tamaño: $WAV_SIZE_HUMAN"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [SOX] Bytes: $WAV_SIZE_BYTES"

  write_state LAST_RECORDING_END_TS "$(date +%s)"
  write_state LAST_WAV "$WAV_PATH"
  write_state LAST_WAV_SIZE_BYTES "$WAV_SIZE_BYTES"
  write_state LAST_STAGE "uploading"

  # --- Envío de datos al servidor de Doñana ---
  echo
  echo "------------------------------------------------------------"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Iniciando envío"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Nombre del audio: $WAV_NAME"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Archivo local: $WAV_PATH"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Tamaño: $WAV_SIZE_HUMAN"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] ID recorder: $IDRECORDER"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Destino: http://10.0.0.114:5000/api/v1/insert_files"
  echo "------------------------------------------------------------"

  curl --fail-with-body \
    --show-error \
    --connect-timeout 15 \
    --max-time 300 \
    -F "json_data={\"file_1\":{\"filename\":\"${WAV_NAME}\",\"id_recorder_recordings\":\"${IDRECORDER}\",\"time_record\":\"${FILE_DATE}\",\"filetype_record\":\".wav\",\"bitrate_record\":\"${BITRATE}\",\"sample_rate_record\":\"${SAMPLE_RATE}\",\"gain_record\":\"${GAIN}\",\"duration_record\":\"${DURATION}\"}}" \
    -F "file_1=@${WAV_PATH};type=audio/wav" \
    "http://10.0.0.114:5000/api/v1/insert_files"

  echo
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Envío finalizado correctamente"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Audio enviado: $WAV_NAME"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CURL] Archivo leído: $WAV_PATH"

  write_state LAST_UPLOAD_TS "$(date +%s)"
  write_state LAST_UPLOAD_FILE "$WAV_NAME"
  write_state LAST_UPLOAD_STATUS "ok"
  write_state LAST_STAGE "spectrogram"

  # Ejemplo antiguo:
  #
  # mkdir -p "$PROGRAMS_DIR/sdBackup/$DIRECTORY"
  # "$PROGRAMS_DIR/spectrogram/spectrogram" \
  #   "$PROGRAMS_DIR/recordings/$WAV_NAME"
  # mv "$PROGRAMS_DIR/recordings/${WAV_NAME}"* \
  #   "$PROGRAMS_DIR/sdBackup/$DIRECTORY/"

  # --- Generación del espectrograma ---
  if [ -x "$SPECTROGRAM_BIN" ]; then
    echo
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SPECTROGRAM] Procesando: $WAV_PATH"

    set +e

    timeout --kill-after=10s \
      "${SPECTROGRAM_TIMEOUT}s" \
      "$SPECTROGRAM_BIN" \
      "$WAV_PATH"

    code="$?"

    set -e

    if [ "$code" -ne 0 ]; then
      write_state LAST_ERROR "spectrogram_failed_exit_${code}"
      write_state LAST_SPECTROGRAM_STATUS "failed"

      echo "$(date '+%Y-%m-%d %H:%M:%S') [SPECTROGRAM] ERROR exit=${code} file=${WAV_PATH}" |
        tee -a "$LOG_FILE" >&2

      exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') [SPECTROGRAM] Finalizado: $WAV_PATH"

    write_state LAST_SPECTROGRAM_STATUS "ok"
    write_state LAST_SPECTROGRAM_TS "$(date +%s)"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SPECTROGRAM] Binario no encontrado: $SPECTROGRAM_BIN"

    write_state LAST_SPECTROGRAM_STATUS "missing"
  fi

  # --- Temperatura de la placa ---
  BOARD_TEMP=""

  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW="$(cat /sys/class/thermal/thermal_zone0/temp)"
    BOARD_TEMP="$(awk '{printf("%d",$1/1000)}' <<< "$TEMP_RAW")"
  fi

  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE $WAV_NAME" >> "$LOG_FILE"
  echo "$FILE_DATE BOARD_TEMP ${BOARD_TEMP}C FILE $WAV_NAME" >> "$STATS_FILE"

  write_state LAST_STATS_TS "$(date +%s)"
  write_state LAST_STAGE "sleeping"

  echo
  echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] Ciclo terminado"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] Audio local: $WAV_PATH"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [RECORDER] Esperando ${SLEEPDURATION}s"
  echo "============================================================"

  # Para mover los archivos a una carpeta por fecha:
  #
  # mkdir -p "$BACKUP_DIR/$DIRECTORY"
  # mv "$WAV_PATH"* "$BACKUP_DIR/$DIRECTORY/" || true

  sleep "$SLEEPDURATION"
done