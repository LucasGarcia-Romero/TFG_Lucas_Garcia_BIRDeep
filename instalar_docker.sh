#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "ERROR: fallo en la linea $LINENO ejecutando: $BASH_COMMAND" >&2' ERR

echo "========================================"
echo " Instalacion de Docker y Docker Compose"
echo "========================================"

# Ejecutar como usuario normal. El script usara sudo cuando sea necesario.
if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: no ejecutes este script directamente como root."
  echo "Usa:"
  echo "  ./install_docker.sh"
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo no esta instalado."
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "ERROR: no se puede leer /etc/os-release."
  exit 1
fi

# Solicitar la contraseña sudo al principio.
sudo -v

# Cargar informacion del sistema.
# shellcheck disable=SC1091
. /etc/os-release

DISTRO_ID="${ID:-}"
DISTRO_LIKE="${ID_LIKE:-}"
CODENAME="${VERSION_CODENAME:-}"
ARCH="$(dpkg --print-architecture)"
INSTALL_USER="${SUDO_USER:-$USER}"

if [ -z "$CODENAME" ]; then
  echo "ERROR: VERSION_CODENAME no aparece en /etc/os-release."
  exit 1
fi

if [ "$DISTRO_ID" != "debian" ] && [[ "$DISTRO_LIKE" != *debian* ]]; then
  echo "ERROR: este script requiere Debian o un derivado compatible."
  echo "ID=${DISTRO_ID}"
  echo "ID_LIKE=${DISTRO_LIKE}"
  exit 1
fi

case "$ARCH" in
  amd64|arm64|armhf)
    ;;
  *)
    echo "AVISO: arquitectura no comprobada expresamente: $ARCH"
    ;;
esac

echo
echo "Sistema:      ${PRETTY_NAME:-desconocido}"
echo "Codename:     $CODENAME"
echo "Arquitectura: $ARCH"
echo "Usuario:      $INSTALL_USER"
echo

echo "[1/9] Comprobando repositorios obsoletos..."

# bullseye-backports ya no esta disponible en los mirrors normales.
# Se comenta para evitar que apt-get update falle.
if [ "$CODENAME" = "bullseye" ]; then
  if grep -qE '^[[:space:]]*deb .*bullseye-backports' \
    /etc/apt/sources.list 2>/dev/null; then

    echo "Desactivando bullseye-backports en /etc/apt/sources.list..."

    sudo sed -i \
      '/^[[:space:]]*deb .*bullseye-backports/s/^/# DESACTIVADO: /' \
      /etc/apt/sources.list
  fi

  if [ -d /etc/apt/sources.list.d ]; then
    while IFS= read -r source_file; do
      if grep -qE '^[[:space:]]*deb .*bullseye-backports' \
        "$source_file" 2>/dev/null; then

        echo "Desactivando bullseye-backports en $source_file..."

        sudo sed -i \
          '/^[[:space:]]*deb .*bullseye-backports/s/^/# DESACTIVADO: /' \
          "$source_file"
      fi
    done < <(
      find /etc/apt/sources.list.d \
        -maxdepth 1 \
        -type f \
        -name '*.list' \
        -print
    )
  fi
fi

echo "[2/9] Actualizando la informacion de paquetes..."

sudo apt-get update --allow-releaseinfo-change

echo "[3/9] Instalando herramientas necesarias..."

sudo apt-get install -y \
  ca-certificates \
  curl

echo "[4/9] Eliminando paquetes Docker incompatibles..."

CONFLICTING_PACKAGES=(
  docker.io
  docker-compose
  docker-doc
  podman-docker
  containerd
  runc
)

INSTALLED_CONFLICTS=()

for package in "${CONFLICTING_PACKAGES[@]}"; do
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
    grep -q "install ok installed"; then
    INSTALLED_CONFLICTS+=("$package")
  fi
done

if [ "${#INSTALLED_CONFLICTS[@]}" -gt 0 ]; then
  echo "Eliminando: ${INSTALLED_CONFLICTS[*]}"
  sudo apt-get remove -y "${INSTALLED_CONFLICTS[@]}"
else
  echo "No se encontraron paquetes incompatibles instalados."
fi

echo "[5/9] Instalando la clave oficial de Docker..."

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL \
  "https://download.docker.com/linux/debian/gpg" \
  -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "[6/9] Configurando el repositorio oficial de Docker..."

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update --allow-releaseinfo-change

echo "[7/9] Instalando Docker Engine y Docker Compose..."

sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

echo "[8/9] Activando Docker y containerd..."

sudo systemctl enable --now containerd
sudo systemctl enable --now docker

echo "[9/9] Configurando Docker para el usuario $INSTALL_USER..."

if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker
fi

sudo usermod -aG docker "$INSTALL_USER"

echo
echo "Comprobando servicios..."

if ! sudo systemctl is-active --quiet docker; then
  echo "ERROR: Docker no esta activo."
  sudo systemctl status docker --no-pager || true
  exit 1
fi

if ! sudo systemctl is-active --quiet containerd; then
  echo "ERROR: containerd no esta activo."
  sudo systemctl status containerd --no-pager || true
  exit 1
fi

echo
echo "Versiones instaladas:"
sudo docker --version
sudo docker compose version
sudo docker buildx version

echo
echo "Ejecutando la prueba hello-world..."
sudo docker run --rm hello-world

echo
echo "========================================"
echo " Instalacion completada correctamente"
echo "========================================"
echo
echo "Cierra la sesion SSH y vuelve a entrar para poder usar Docker sin sudo."
echo
echo "Despues comprueba:"
echo "  docker --version"
echo "  docker compose version"
echo "  docker run --rm hello-world"
echo
echo "Para iniciar el proyecto:"
echo "  cd /home/orangepi/pruebas_grabadora"
echo "  docker compose build"
echo "  docker compose up -d"
echo "  docker compose ps"