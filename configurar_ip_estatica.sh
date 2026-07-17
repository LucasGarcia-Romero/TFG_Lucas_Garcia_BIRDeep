```bash
#!/usr/bin/env bash

set -euo pipefail

CONEXION="Wired connection 1"

IP="192.168.5.161"
PREFIJO="24"
MASCARA="255.255.255.0"

GATEWAY="192.168.5.1"
DNS="1.1.1.1 8.8.8.8"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli no está instalado."
    echo "Instálalo con:"
    echo "sudo apt update && sudo apt install network-manager"
    exit 1
fi

if ! nmcli connection show "$CONEXION" >/dev/null 2>&1; then
    echo "Error: no existe la conexión: $CONEXION"
    echo
    echo "Conexiones disponibles:"
    nmcli connection show
    exit 1
fi

echo
echo "========================================"
echo "       CONFIGURACIÓN DE RED"
echo "========================================"
echo
echo "Conexión:     $CONEXION"
echo "IP:           $IP"
echo "Máscara:      $MASCARA"
echo "Prefijo CIDR: /$PREFIJO"
echo "Gateway:      $GATEWAY"
echo "DNS:          $DNS"
echo
echo "Al aplicar la configuración, la conexión"
echo "de red se reiniciará."
echo

while true; do
    read -r -p "¿Deseas aplicar esta configuración? [s/n]: " RESPUESTA

    case "${RESPUESTA,,}" in
        s|si|sí|y|yes)
            echo
            echo "Configuración confirmada."
            break
            ;;
        n|no)
            echo
            echo "Operación cancelada. No se realizaron cambios."
            exit 0
            ;;
        *)
            echo "Respuesta no válida. Escribe 's' o 'n'."
            ;;
    esac
done

echo
echo "Configurando $CONEXION..."

sudo nmcli connection modify "$CONEXION" \
    ipv4.method manual \
    ipv4.addresses "$IP/$PREFIJO" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS"

echo "Reiniciando la conexión..."

sudo nmcli connection down "$CONEXION" || true
sudo nmcli connection up "$CONEXION"

echo
echo "========================================"
echo "     CONFIGURACIÓN APLICADA"
echo "========================================"
echo

echo "Direcciones IPv4:"
ip -4 address

echo
echo "Tabla de rutas:"
ip route

echo
echo "DNS configurados:"
nmcli connection show "$CONEXION" |
    grep -E '^ipv4\.dns|^ipv4\.addresses|^ipv4\.gateway'
```
