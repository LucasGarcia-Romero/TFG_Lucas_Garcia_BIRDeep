#!/usr/bin/env bash

set -e

CONEXION="Wired connection 1"
IP="192.168.1.50/24"
GATEWAY="192.168.1.1"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli no está instalado."
    echo "Instálalo con: sudo apt update && sudo apt install network-manager"
    exit 1
fi

echo "Configurando IP estática en: $CONEXION"

sudo nmcli connection modify "$CONEXION" \
    ipv4.method manual \
    ipv4.addresses "$IP" \
    ipv4.gateway "$GATEWAY"

echo "Reiniciando la conexión..."

sudo nmcli connection down "$CONEXION" || true
sudo nmcli connection up "$CONEXION"

echo "Configuración aplicada."
ip -4 address
ip route