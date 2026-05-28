#!/bin/bash
set -euo pipefail

RECORDER_CONTAINER="${RECORDER_CONTAINER:-bird-recorder}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
DATA_DIR="${DATA_DIR:-/data}"
RECORDINGS_DIR="$DATA_DIR/recordings"
STATS_FILE="$DATA_DIR/stats.txt"
RESTART_COOLDOWN="${WATCHDOG_RESTART_COOLDOWN_SECONDS:-300}"
LAST_RESTART_FILE="/tmp/recorder-watchdog-last-restart"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $*"
}

restart_recorder() {
  reason="$1"
  now="$(date +%s)"
  last="0"
  [ -f "$LAST_RESTART_FILE" ] && last="$(cat "$LAST_RESTART_FILE" 2>/dev/null || echo 0)"
  elapsed=$((now - last))

  if [ "$elapsed" -lt "$RESTART_COOLDOWN" ]; then
    log "fallo detectado pero no reinicio por cooldown (${elapsed}s < ${RESTART_COOLDOWN}s): $reason"
    return 0
  fi

  log "reiniciando ${RECORDER_CONTAINER}: $reason"
  echo "$now" > "$LAST_RESTART_FILE"
  docker restart "$RECORDER_CONTAINER" >/dev/null
}

container_running() {
  docker inspect -f '{{.State.Running}}' "$RECORDER_CONTAINER" 2>/dev/null | grep -q '^true$'
}

health_status() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$RECORDER_CONTAINER" 2>/dev/null || echo "missing"
}

# Espera inicial: evita reiniciar mientras Docker crea el recorder.
while ! docker inspect "$RECORDER_CONTAINER" >/dev/null 2>&1; do
  log "esperando a que exista el contenedor ${RECORDER_CONTAINER}"
  sleep 10
 done

log "watchdog iniciado para ${RECORDER_CONTAINER}; intervalo=${CHECK_INTERVAL}s"

while true; do
  if ! container_running; then
    restart_recorder "contenedor no esta running"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  status="$(health_status)"
  case "$status" in
    healthy|starting|none)
      log "estado=${status}"
      ;;
    unhealthy)
      detail="$(docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' "$RECORDER_CONTAINER" 2>/dev/null | tail -c 500 || true)"
      restart_recorder "healthcheck unhealthy ${detail}"
      ;;
    *)
      restart_recorder "estado health inesperado: ${status}"
      ;;
  esac

  sleep "$CHECK_INTERVAL"
done
