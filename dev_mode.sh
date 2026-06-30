#!/bin/bash
# Para o AP e conecta ao WiFi salvo para desenvolvimento.
# Uso: sudo ./dev_mode.sh [nome_da_conexao]
# Exemplo: sudo ./dev_mode.sh SALTE

CONEXAO="${1:-SALTE}"

echo "Parando wifi-manager e AP..."
systemctl stop wifi-manager.service 2>/dev/null || true
pkill hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

echo "Liberando wlan0 para o NetworkManager..."
rm -f /etc/NetworkManager/conf.d/99-ap-mode.conf
nmcli general reload conf 2>/dev/null || true
sleep 3
rfkill unblock wifi 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
ip link set wlan0 down 2>/dev/null || true
sleep 1
ip link set wlan0 up

echo "Conectando a '$CONEXAO'..."
if nmcli connection up "$CONEXAO" ifname wlan0; then
    echo "Conectado. IP: $(hostname -I | awk '{print $1}')"
else
    echo "Falha ao conectar '$CONEXAO'."
    echo "Redes salvas disponíveis:"
    nmcli -t -f NAME,TYPE connection show | grep wifi
fi
