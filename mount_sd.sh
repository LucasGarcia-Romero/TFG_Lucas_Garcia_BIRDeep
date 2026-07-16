#!/usr/bin/env bash
set -Eeuo pipefail

MOUNT_POINT="/data"
COMPOSE_DIR="/home/orangepi/pruebas_grabadora"

echo "Buscando una SD o unidad de datos..."

# Dispositivo donde está instalado el sistema raíz.
ROOT_SOURCE="$(findmnt -n -o SOURCE /)"
ROOT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)"

# Busca particiones con sistema de archivos y UUID que no pertenezcan
# al disco donde está instalado Armbian.
mapfile -t CANDIDATES < <(
    lsblk -rpn -o NAME,TYPE,FSTYPE,UUID |
    awk '$2 == "part" && $3 != "" && $4 != "" {print $1}' |
    while read -r partition; do
        parent="/dev/$(lsblk -no PKNAME "$partition" 2>/dev/null || true)"

        if [[ "$partition" != "$ROOT_SOURCE" && "$parent" != "$ROOT_DISK" ]]; then
            echo "$partition"
        fi
    done
)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "ERROR: no se ha encontrado ninguna SD de datos válida." >&2
    echo "Dispositivos disponibles:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS
    exit 1
fi

if [[ ${#CANDIDATES[@]} -gt 1 ]]; then
    echo "ERROR: se han encontrado varias particiones posibles:" >&2

    for partition in "${CANDIDATES[@]}"; do
        lsblk -no NAME,SIZE,FSTYPE,UUID,LABEL,MOUNTPOINTS "$partition"
    done

    echo "No se monta ninguna para evitar elegir la unidad incorrecta." >&2
    exit 1
fi

DEVICE="${CANDIDATES[0]}"
UUID="$(lsblk -no UUID "$DEVICE" | xargs)"
FSTYPE="$(lsblk -no FSTYPE "$DEVICE" | xargs)"

echo "Partición detectada: $DEVICE"
echo "UUID detectado:      $UUID"
echo "Sistema de archivos: $FSTYPE"

sudo mkdir -p "$MOUNT_POINT"

# Comprueba si /data ya está montado.
if mountpoint -q "$MOUNT_POINT"; then
    CURRENT_DEVICE="$(findmnt -n -o SOURCE --target "$MOUNT_POINT")"
    CURRENT_UUID="$(lsblk -no UUID "$CURRENT_DEVICE" 2>/dev/null | xargs || true)"

    if [[ "$CURRENT_UUID" != "$UUID" ]]; then
        echo "ERROR: $MOUNT_POINT ya está montado desde otra unidad:" >&2
        findmnt "$MOUNT_POINT"
        exit 1
    fi

    echo "La SD ya está montada correctamente."
else
    echo "Montando UUID=$UUID en $MOUNT_POINT..."

    sudo mount -t "$FSTYPE" \
        -o rw,noatime \
        "/dev/disk/by-uuid/$UUID" \
        "$MOUNT_POINT"
fi

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERROR: no se pudo montar la SD." >&2
    exit 1
fi

echo
echo "Montaje confirmado:"
findmnt "$MOUNT_POINT"
df -hT "$MOUNT_POINT"

# Crea los directorios utilizados por el proyecto.
sudo mkdir -p \
    "$MOUNT_POINT/recordings" \
    "$MOUNT_POINT/sdBackup"

cd "$COMPOSE_DIR"

echo
echo "Iniciando Docker Compose..."
docker compose up -d --build

echo
echo "Contenedores:"
docker compose ps