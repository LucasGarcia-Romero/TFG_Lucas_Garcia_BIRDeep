#!/bin/bash
set -euo pipefail

# Watchdog multiservicio con cooldown fijo + backoff largo.
#
# Comportamiento:
#   - Revisa todos los contenedores definidos en WATCHDOG_CONTAINERS.
#   - Si un contenedor no esta running, lo reinicia.
#   - Si un contenedor esta unhealthy, lo reinicia.
#   - Cada contenedor tiene cooldown independiente.
#   - Si un contenedor acumula demasiados reinicios dentro de una ventana temporal,
#     entra en backoff largo para evitar bucles agresivos.
#
# Variables recomendadas:
#
#   WATCHDOG_CONTAINERS=bird-recorder,bird-stats,bird-http-server
#   CHECK_INTERVAL=60
#   WATCHDOG_RESTART_COOLDOWN_SECONDS=300
#   WATCHDOG_FAILURE_WINDOW_SECONDS=1800
#   WATCHDOG_MAX_RESTARTS_IN_WINDOW=3
#   WATCHDOG_LONG_COOLDOWN_SECONDS=1800
#
# Compatibilidad:
#   Si WATCHDOG_CONTAINERS no existe, usa RECORDER_CONTAINER.
#   Si RECORDER_CONTAINER tampoco existe, usa bird-recorder.

WATCHDOG_CONTAINERS="${WATCHDOG_CONTAINERS:-${RECORDER_CONTAINER:-bird-recorder}}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

# Cooldown normal entre reinicios del mismo contenedor.
RESTART_COOLDOWN="${WATCHDOG_RESTART_COOLDOWN_SECONDS:-300}"

# Ventana temporal para contar fallos repetidos.
FAILURE_WINDOW="${WATCHDOG_FAILURE_WINDOW_SECONDS:-1800}"

# Maximo de reinicios permitidos dentro de FAILURE_WINDOW antes de activar backoff largo.
MAX_RESTARTS_IN_WINDOW="${WATCHDOG_MAX_RESTARTS_IN_WINDOW:-3}"

# Backoff largo cuando hay demasiados reinicios en la ventana.
LONG_COOLDOWN="${WATCHDOG_LONG_COOLDOWN_SECONDS:-1800}"

STATE_DIR="${WATCHDOG_STATE_DIR:-/tmp/watchdog-state}"
mkdir -p "$STATE_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $*"
}

trim() {
  echo "$1" | xargs
}

safe_name() {
  # Los nombres de contenedores suelen ser seguros, pero quitamos caracteres raros
  # por si algun nombre llega con slash u otros simbolos.
  echo "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

last_restart_file_for() {
  local container="$1"
  echo "$STATE_DIR/$(safe_name "$container").last-restart"
}

restart_history_file_for() {
  local container="$1"
  echo "$STATE_DIR/$(safe_name "$container").restart-history"
}

backoff_until_file_for() {
  local container="$1"
  echo "$STATE_DIR/$(safe_name "$container").backoff-until"
}

container_exists() {
  local container="$1"
  docker inspect "$container" >/dev/null 2>&1
}

container_running() {
  local container="$1"
  docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q '^true$'
}

container_state() {
  local container="$1"
  docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing"
}

health_status() {
  local container="$1"
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "missing"
}

health_detail() {
  local container="$1"

  # Ultimos mensajes del healthcheck, limitados para no llenar los logs.
  docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' "$container" 2>/dev/null | tail -c 700 || true
}

now_epoch() {
  date +%s
}

read_number_file() {
  local file="$1"
  local default_value="${2:-0}"

  if [ -f "$file" ]; then
    cat "$file" 2>/dev/null | grep -E '^[0-9]+$' || echo "$default_value"
  else
    echo "$default_value"
  fi
}

cleanup_restart_history() {
  local container="$1"
  local now="$2"
  local history_file
  local cutoff
  local tmp_file

  history_file="$(restart_history_file_for "$container")"
  cutoff=$((now - FAILURE_WINDOW))
  tmp_file="${history_file}.tmp"

  if [ ! -f "$history_file" ]; then
    : > "$history_file"
    return 0
  fi

  awk -v cutoff="$cutoff" '$1 >= cutoff { print $1 }' "$history_file" > "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$history_file"
}

restart_count_in_window() {
  local container="$1"
  local now="$2"
  local history_file

  history_file="$(restart_history_file_for "$container")"
  cleanup_restart_history "$container" "$now"

  if [ ! -f "$history_file" ]; then
    echo 0
    return 0
  fi

  wc -l < "$history_file" | xargs
}

record_restart() {
  local container="$1"
  local now="$2"
  local last_file
  local history_file

  last_file="$(last_restart_file_for "$container")"
  history_file="$(restart_history_file_for "$container")"

  echo "$now" > "$last_file"
  echo "$now" >> "$history_file"

  cleanup_restart_history "$container" "$now"
}

backoff_remaining() {
  local container="$1"
  local now="$2"
  local file
  local until
  local remaining

  file="$(backoff_until_file_for "$container")"
  until="$(read_number_file "$file" 0)"

  if [ "$until" -le "$now" ]; then
    echo 0
    return 0
  fi

  remaining=$((until - now))
  echo "$remaining"
}

activate_long_backoff() {
  local container="$1"
  local now="$2"
  local file
  local until

  file="$(backoff_until_file_for "$container")"
  until=$((now + LONG_COOLDOWN))

  echo "$until" > "$file"
  log "${container}: backoff largo activado durante ${LONG_COOLDOWN}s"
}

can_restart_now() {
  local container="$1"
  local now
  local last
  local elapsed
  local remaining
  local last_file

  now="$(now_epoch)"

  remaining="$(backoff_remaining "$container" "$now")"
  if [ "$remaining" -gt 0 ]; then
    log "${container}: fallo detectado, pero esta en backoff largo (${remaining}s restantes)"
    return 1
  fi

  last_file="$(last_restart_file_for "$container")"
  last="$(read_number_file "$last_file" 0)"
  elapsed=$((now - last))

  if [ "$elapsed" -lt "$RESTART_COOLDOWN" ]; then
    log "${container}: fallo detectado, pero no reinicio por cooldown (${elapsed}s < ${RESTART_COOLDOWN}s)"
    return 1
  fi

  return 0
}

restart_container() {
  local container="$1"
  local reason="$2"
  local now
  local count_before
  local count_after

  if ! can_restart_now "$container"; then
    return 0
  fi

  now="$(now_epoch)"
  count_before="$(restart_count_in_window "$container" "$now")"

  if [ "$count_before" -ge "$MAX_RESTARTS_IN_WINDOW" ]; then
    activate_long_backoff "$container" "$now"
    log "${container}: no reinicio porque ya lleva ${count_before} reinicios en los ultimos ${FAILURE_WINDOW}s"
    return 0
  fi

  log "${container}: reiniciando. Motivo: ${reason}"

  if docker restart "$container" >/dev/null; then
    record_restart "$container" "$now"
    count_after="$(restart_count_in_window "$container" "$now")"
    log "${container}: reinicio completado (${count_after}/${MAX_RESTARTS_IN_WINDOW} reinicios en ventana de ${FAILURE_WINDOW}s)"

    if [ "$count_after" -ge "$MAX_RESTARTS_IN_WINDOW" ]; then
      activate_long_backoff "$container" "$now"
    fi
  else
    log "${container}: ERROR reiniciando"
    return 1
  fi
}

check_container() {
  local container="$1"
  local status
  local state
  local detail

  if ! container_exists "$container"; then
    log "${container}: no existe todavia; saltando"
    return 0
  fi

  if ! container_running "$container"; then
    state="$(container_state "$container")"
    restart_container "$container" "contenedor no esta running; estado=${state}"
    return 0
  fi

  status="$(health_status "$container")"

  case "$status" in
    healthy)
      log "${container}: healthy"
      ;;

    starting)
      log "${container}: starting"
      ;;

    none)
      # Contenedor sin HEALTHCHECK. Si esta running, lo consideramos OK.
      log "${container}: running sin healthcheck"
      ;;

    unhealthy)
      detail="$(health_detail "$container")"
      if [ -n "$detail" ]; then
        restart_container "$container" "healthcheck unhealthy: ${detail}"
      else
        restart_container "$container" "healthcheck unhealthy"
      fi
      ;;

    missing)
      log "${container}: no se pudo inspeccionar"
      ;;

    *)
      restart_container "$container" "estado health inesperado: ${status}"
      ;;
  esac
}

IFS=',' read -ra RAW_CONTAINERS <<< "$WATCHDOG_CONTAINERS"

CONTAINERS=()
for raw_container in "${RAW_CONTAINERS[@]}"; do
  container="$(trim "$raw_container")"
  if [ -n "$container" ]; then
    CONTAINERS+=("$container")
  fi
done

if [ "${#CONTAINERS[@]}" -eq 0 ]; then
  log "ERROR: WATCHDOG_CONTAINERS esta vacio"
  exit 1
fi

log "watchdog multiservicio iniciado con backoff"
log "contenedores: ${CONTAINERS[*]}"
log "intervalo: ${CHECK_INTERVAL}s"
log "cooldown normal por contenedor: ${RESTART_COOLDOWN}s"
log "ventana de fallos: ${FAILURE_WINDOW}s"
log "max reinicios por ventana: ${MAX_RESTARTS_IN_WINDOW}"
log "cooldown largo/backoff: ${LONG_COOLDOWN}s"

while true; do
  for container in "${CONTAINERS[@]}"; do
    check_container "$container"
  done

  sleep "$CHECK_INTERVAL"
done
