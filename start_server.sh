#!/bin/bash
# Start Bluetooth PAN + Flask image gallery.
# Usage: sudo ./start_server.sh /path/to/images/folder

set -e

PI_IP="192.168.50.1"
PORT=8080
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- argument check ---
if [ -z "$1" ]; then
    echo "Usage: sudo $0 /path/to/images/folder"
    exit 1
fi

IMAGE_DIR="$(realpath "$1")"

if [ ! -d "$IMAGE_DIR" ]; then
    echo "ERROR: Directory not found: $IMAGE_DIR"
    exit 1
fi

# --- cleanup on exit ---
cleanup() {
    echo ""
    echo "[BT-PAN] Shutting down..."
    kill "$BT_NET_PID" 2>/dev/null || true
    kill "$FLASK_PID" 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    ip link set pan0 down 2>/dev/null || true
    ip link delete pan0 type bridge 2>/dev/null || true
    bluetoothctl discoverable off 2>/dev/null || true
    echo "[BT-PAN] Done."
}
trap cleanup EXIT INT TERM

# --- create pan0 bridge interface ---
echo "[BT-PAN] Setting up pan0 interface..."
if ip link show pan0 &>/dev/null; then
    ip link delete pan0 type bridge 2>/dev/null || true
fi
ip link add name pan0 type bridge
ip link set pan0 up
ip addr add "$PI_IP/24" dev pan0
echo "[BT-PAN] Interface pan0 ready — IP $PI_IP"

# --- start dnsmasq for DHCP ---
echo "[BT-PAN] Starting dnsmasq..."
systemctl start dnsmasq
echo "[BT-PAN] dnsmasq started"

# --- start Bluetooth NAP service ---
echo "[BT-PAN] Starting Bluetooth NAP service..."
bt-network -s nap pan0 &
BT_NET_PID=$!
sleep 1
echo "[BT-PAN] NAP service started (PID $BT_NET_PID)"

# --- make discoverable ---
echo "[BT-PAN] Enabling Bluetooth discoverability..."
bluetoothctl power on
bluetoothctl discoverable on
bluetoothctl pairable on
echo "[BT-PAN] Bluetooth discoverable"

# --- start Flask gallery ---
echo "[GALLERY] Serving $IMAGE_DIR on port $PORT"
echo "[GALLERY] Open on phone: http://$PI_IP:$PORT"
echo "---"
IMAGE_DIR="$IMAGE_DIR" python3 "$SCRIPT_DIR/gallery.py" &
FLASK_PID=$!

# keep running until Ctrl+C
wait "$FLASK_PID"
