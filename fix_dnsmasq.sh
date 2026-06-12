#!/bin/bash
# Run this on the Pi as root: sudo ./fix_dnsmasq.sh

set -e

echo "=== Rewriting dnsmasq config ==="
cat > /etc/dnsmasq.d/bluetooth-pan.conf << 'EOF'
interface=pan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-authoritative
dhcp-broadcast
dhcp-range=::1,::ffff,constructor:pan0,ra-only,64,24h
EOF

echo "=== Restarting dnsmasq ==="
systemctl restart dnsmasq

echo "=== dnsmasq status ==="
journalctl -u dnsmasq -n 10 --no-pager
