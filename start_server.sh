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
    ip6tables -D INPUT  -i pan0 -j ACCEPT 2>/dev/null || true
    ip6tables -D FORWARD -i pan0 -j ACCEPT 2>/dev/null || true
    iptables  -D INPUT  -i pan0 -j ACCEPT 2>/dev/null || true
    iptables  -D FORWARD -i pan0 -j ACCEPT 2>/dev/null || true
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
# disable STP so bnep0 forwards immediately when the phone connects
ip link set pan0 type bridge stp_state 0
ip link set pan0 up
ip addr add "$PI_IP/24" dev pan0
# prevent br_netfilter from routing bridge frames through iptables FORWARD
sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
ip -6 addr add fd00::1/64 dev pan0 2>/dev/null || true
# allow pan0 traffic through iptables regardless of Docker's DROP policy
ip6tables -C INPUT  -i pan0 -j ACCEPT 2>/dev/null || ip6tables -I INPUT  -i pan0 -j ACCEPT
ip6tables -C FORWARD -i pan0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD -i pan0 -j ACCEPT
iptables  -C INPUT  -i pan0 -j ACCEPT 2>/dev/null || iptables  -I INPUT  -i pan0 -j ACCEPT
iptables  -C FORWARD -i pan0 -j ACCEPT 2>/dev/null || iptables  -I FORWARD -i pan0 -j ACCEPT
echo "[BT-PAN] Interface pan0 ready — IP $PI_IP / IPv6 fd00::1"

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
