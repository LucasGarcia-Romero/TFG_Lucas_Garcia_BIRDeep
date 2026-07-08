#!/bin/bash

# Uso:
# ./conectar_wifi.sh "NOMBRE_WIFI" "CONTRASEÑA_WIFI"

# Permisos
# chmod +x conectar_wifi.sh

SSID="$1"
PASSWORD="$2"

if [ -z "$SSID" ] || [ -z "$PASSWORD" ]; then
    echo "Uso: $0 \"NOMBRE_WIFI\" \"CONTRASEÑA_WIFI\""
    exit 1
fi

if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli no está instalado."
    echo "Instala NetworkManager primero:"
    echo "sudo apt update && sudo apt install network-manager -y"
    exit 1
fi

echo "Activando NetworkManager..."
sudo systemctl enable NetworkManager >/dev/null 2>&1
sudo systemctl start NetworkManager

echo "Activando WiFi..."
sudo nmcli radio wifi on

echo "Buscando redes WiFi..."
sudo nmcli device wifi rescan
sleep 2

echo "Conectando a la red '$SSID'..."
sudo nmcli device wifi connect "$SSID" password "$PASSWORD"

if [ $? -ne 0 ]; then
    echo "Error: no se pudo conectar a '$SSID'"
    exit 1
fi

echo "Configurando autoconexión al reiniciar..."
sudo nmcli connection modify "$SSID" connection.autoconnect yes

echo "Conexión realizada correctamente."
echo "La Orange Pi debería conectarse automáticamente después de reiniciar."

echo ""
echo "Estado de la conexión:"
nmcli connection show --active

echo ""
echo "Dirección IP:"
ip addr show | grep "inet " | grep -v "127.0.0.1"