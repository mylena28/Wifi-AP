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

echo "=== [1/5] Installing Bluetooth PAN dependencies ==="
apt update
apt install -y bluez bluez-tools dnsmasq tcpdump

# Persist bridge-netfilter settings so they survive reboot.
# br_netfilter routes bridge traffic through iptables; disabling it prevents
# a default DROP FORWARD policy from blocking DHCP and HTTP on pan0.
cat > /etc/sysctl.d/10-bridge-nf.conf <<'EOF'
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
EOF
sysctl --system 2>/dev/null | grep bridge-nf || true

echo "=== [2/5] Writing .env for Docker ==="
echo "IMAGE_DIR=$IMAGE_DIR" > "$SCRIPT_DIR/.env"
echo "Written: IMAGE_DIR=$IMAGE_DIR"

echo "=== [3/5] Building Docker image ==="
cd "$SCRIPT_DIR"
docker compose build

echo "=== [4/5] Installing Bluetooth PAN systemd service ==="
cp "$SCRIPT_DIR/dnsmasq_pan.conf" /etc/dnsmasq.d/bluetooth-pan.conf
cp "$SCRIPT_DIR/bluetooth-pan.service" /etc/systemd/system/bluetooth-pan.service
systemctl daemon-reload
systemctl enable bluetooth-pan.service
# dnsmasq must only start when bluetooth-pan triggers it, not on boot alone
systemctl disable dnsmasq
systemctl stop dnsmasq 2>/dev/null || true

echo "=== [5/5] Starting services ==="
systemctl enable bluetooth
systemctl restart bluetooth
# remove leftover pan0 before starting (avoids "already exists" error)
ip link set pan0 down 2>/dev/null; ip link delete pan0 2>/dev/null; true
systemctl start bluetooth-pan.service
docker compose up -d

echo ""
echo "=== Setup complete ==="
echo "Image folder : $IMAGE_DIR"
echo "Gallery URL  : http://192.168.50.1:8080"
echo ""
echo "Next step: pair your phone — see README.md Part 1.3"
