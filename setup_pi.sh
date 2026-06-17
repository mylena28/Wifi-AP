#!/bin/bash
# One-time setup — run once on the Pi as root.
# Usage: sudo ./setup_pi.sh /path/to/images/folder

set -e

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

echo "=== [0/5] Removing old Bluetooth PAN setup (if present) ==="
systemctl stop bluetooth-pan.service 2>/dev/null || true
systemctl disable bluetooth-pan.service 2>/dev/null || true
rm -f /etc/systemd/system/bluetooth-pan.service
rm -f /etc/dnsmasq.d/bluetooth-pan.conf
ip link set pan0 down 2>/dev/null || true
ip link delete pan0 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

echo "=== [1/5] Installing Wi-Fi AP dependencies ==="
apt update
apt install -y hostapd dnsmasq

echo "=== [2/5] Writing .env for Docker ==="
echo "IMAGE_DIR=$IMAGE_DIR" > "$SCRIPT_DIR/.env"
echo "Written: IMAGE_DIR=$IMAGE_DIR"

echo "=== [3/5] Building Docker image ==="
cd "$SCRIPT_DIR"
docker compose build

echo "=== [4/5] Configuring Wi-Fi Access Point ==="
# Tell NetworkManager to leave wlan0 alone
nmcli device set wlan0 managed no 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true

# Copy configs
mkdir -p /etc/hostapd
cp "$SCRIPT_DIR/hostapd.conf"    /etc/hostapd/hostapd.conf
cp "$SCRIPT_DIR/dnsmasq_wifi.conf" /etc/dnsmasq.d/wifi-ap.conf

# Install systemd service
cp "$SCRIPT_DIR/wifi-ap.service" /etc/systemd/system/wifi-ap.service
systemctl daemon-reload
systemctl enable wifi-ap.service

# dnsmasq starts on demand from wifi-ap.service, not on boot
systemctl disable dnsmasq
systemctl stop dnsmasq 2>/dev/null || true

echo "=== [5/5] Starting services ==="
systemctl start wifi-ap.service
docker compose up -d

echo ""
echo "=== Setup complete ==="
echo "Image folder  : $IMAGE_DIR"
echo "Wi-Fi SSID    : PiGaleria"
echo "Wi-Fi password: piimagens"
echo "Gallery URL   : http://192.168.50.1:8080"
echo ""
echo "Next step: connect your phone to Wi-Fi 'PiGaleria' and open http://192.168.50.1:8080"
