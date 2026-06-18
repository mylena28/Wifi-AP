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

echo "=== [0/6] Removendo setup antigo (Bluetooth PAN / wifi-ap) ==="
systemctl stop bluetooth-pan.service 2>/dev/null || true
systemctl disable bluetooth-pan.service 2>/dev/null || true
rm -f /etc/systemd/system/bluetooth-pan.service
rm -f /etc/dnsmasq.d/bluetooth-pan.conf
ip link set pan0 down 2>/dev/null || true
ip link delete pan0 2>/dev/null || true

systemctl stop wifi-ap.service 2>/dev/null || true
systemctl disable wifi-ap.service 2>/dev/null || true

systemctl stop wifi-manager.service 2>/dev/null || true
systemctl disable wifi-manager.service 2>/dev/null || true

systemctl daemon-reload 2>/dev/null || true

echo "=== [1/6] Instalando dependências ==="
apt update
apt install -y hostapd dnsmasq

# hostapd precisa estar desmascarado
systemctl unmask hostapd 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true  # gerenciado pelo wifi_manager
systemctl disable dnsmasq 2>/dev/null || true  # gerenciado pelo wifi_manager
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

echo "=== [2/6] Escrevendo .env para o Docker ==="
echo "IMAGE_DIR=$IMAGE_DIR" > "$SCRIPT_DIR/.env"
echo "  IMAGE_DIR=$IMAGE_DIR"

echo "=== [3/6] Build da imagem Docker ==="
cd "$SCRIPT_DIR"
docker compose build

echo "=== [4/6] Configurando Wi-Fi AP ==="
rfkill unblock wifi 2>/dev/null || true

mkdir -p /etc/hostapd
cp "$SCRIPT_DIR/hostapd.conf"       /etc/hostapd/hostapd.conf
cp "$SCRIPT_DIR/dnsmasq_wifi.conf"  /etc/dnsmasq.d/wifi-ap.conf

echo "=== [5/6] Instalando wifi_manager + backup ==="

mkdir -p /etc/wifi_manager

# Arquivo de redes conhecidas
if [ ! -f /etc/wifi_manager/networks.conf ]; then
    cp "$SCRIPT_DIR/networks.conf" /etc/wifi_manager/networks.conf
    echo "  networks.conf criado em /etc/wifi_manager/"
else
    echo "  networks.conf já existe — mantendo configuração atual."
fi
chmod 664 /etc/wifi_manager/networks.conf

# Configuração de backup
if [ ! -f /etc/wifi_manager/backup.conf ]; then
    cp "$SCRIPT_DIR/backup.conf" /etc/wifi_manager/backup.conf
    echo "  backup.conf criado em /etc/wifi_manager/"
else
    echo "  backup.conf já existe — mantendo configuração atual."
fi
chmod 664 /etc/wifi_manager/backup.conf

# Copia o .env para /etc/wifi_manager/ para o sync_backup.sh ler
cp "$SCRIPT_DIR/.env" /etc/wifi_manager/.env

# Scripts principais
cp "$SCRIPT_DIR/wifi_manager.sh"  /usr/local/bin/wifi_manager.sh
cp "$SCRIPT_DIR/sync_backup.sh"   /usr/local/bin/sync_backup.sh
chmod +x /usr/local/bin/wifi_manager.sh /usr/local/bin/sync_backup.sh

# Chave SSH para rsync sem senha
SSH_KEY="/root/.ssh/wifi_manager_backup"
if [ ! -f "$SSH_KEY" ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "wifi_manager_backup@$(hostname)" -q
    echo "  Chave SSH gerada: $SSH_KEY"
fi

# Serviço systemd
cp "$SCRIPT_DIR/wifi-manager.service" /etc/systemd/system/wifi-manager.service
systemctl daemon-reload
systemctl enable wifi-manager.service

# Docker sobe no boot (restart:always cuida do container)
systemctl enable docker 2>/dev/null || true

echo "=== [6/6] Iniciando serviços ==="
docker compose up -d
systemctl start wifi-manager.service

echo ""
echo "=== Setup completo ==="
echo "  Pasta de imagens  : $IMAGE_DIR"
echo "  Wi-Fi SSID        : PiGaleria"
echo "  Wi-Fi senha       : piimagens"
echo "  Galeria (AP)      : http://192.168.50.1:8080"
echo "  Gerenciar redes   : http://192.168.50.1:8080/redes"
echo ""
echo "  Editar redes salvas : /etc/wifi_manager/networks.conf"
echo "  Configurar backup   : /etc/wifi_manager/backup.conf"
echo "  Logs em tempo real  : journalctl -fu wifi-manager.service"
echo ""
echo "--- BACKUP (passo manual único) ---"
echo "Quando tiver o IP do Pi backup, edite /etc/wifi_manager/backup.conf"
echo "e rode o comando abaixo para autorizar o acesso SSH:"
echo ""
echo "  ssh-copy-id -i ${SSH_KEY}.pub pi@<ip-do-backup>"
echo ""
echo "Conecte o celular ao Wi-Fi 'PiGaleria' e abra http://192.168.50.1:8080"
