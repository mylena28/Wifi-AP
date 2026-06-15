#!/bin/bash
# Manual start — Wi-Fi AP + Flask gallery (without Docker).
# Usage: sudo ./start_server.sh /path/to/images/folder

set -e

PI_IP="192.168.50.1"
PORT=8080
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
    echo "Usage: sudo $0 /path/to/images/folder"
    exit 1
fi

IMAGE_DIR="$(realpath "$1")"

if [ ! -d "$IMAGE_DIR" ]; then
    echo "ERROR: Directory not found: $IMAGE_DIR"
    exit 1
fi

cleanup() {
    echo ""
    echo "[WIFI-AP] Shutting down..."
    kill "$HOSTAPD_PID" 2>/dev/null || true
    kill "$FLASK_PID"   2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    iptables -t nat -D PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null || true
    iptables -D INPUT   -i wlan0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i wlan0 -j ACCEPT 2>/dev/null || true
    ip addr flush dev wlan0 2>/dev/null || true
    echo "[WIFI-AP] Done."
}
trap cleanup EXIT INT TERM

echo "[WIFI-AP] Setting up wlan0..."
nmcli device set wlan0 managed no 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
ip addr add "$PI_IP/24" dev wlan0
ip link set wlan0 up

iptables -t nat -C PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port "$PORT" 2>/dev/null \
    || iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port "$PORT"
iptables -C INPUT   -i wlan0 -j ACCEPT 2>/dev/null || iptables -I INPUT   -i wlan0 -j ACCEPT
iptables -C FORWARD -i wlan0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i wlan0 -j ACCEPT

echo "[WIFI-AP] Starting hostapd..."
hostapd /etc/hostapd/hostapd.conf &
HOSTAPD_PID=$!
sleep 1

echo "[WIFI-AP] Starting dnsmasq..."
systemctl restart dnsmasq

echo "[GALLERY] Serving $IMAGE_DIR on port $PORT"
echo "[GALLERY] Connect phone to Wi-Fi 'PiGaleria' (password: piimagens)"
echo "[GALLERY] Then open: http://$PI_IP:$PORT"
echo "---"
IMAGE_DIR="$IMAGE_DIR" python3 "$SCRIPT_DIR/gallery.py" &
FLASK_PID=$!

wait "$FLASK_PID"
