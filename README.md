# AppInstalacao — Bluetooth PAN + Flask Image Gallery

Browse images from the Raspberry Pi 5 on your phone via Bluetooth.
No internet or Wi-Fi required. Everything starts automatically on boot.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              Raspberry Pi 5                  │
│                                             │
│  [systemd: bluetooth-pan.service]           │
│    • Creates pan0 interface (192.168.50.1)  │
│    • Starts dnsmasq (DHCP for phone)        │
│    • Starts bt-network NAP                  │
│    • Makes Pi discoverable                  │
│                                             │
│  [Docker: gallery container]                │
│    • Flask image gallery on port 8080       │
│    • Mounts your image folder (read-only)   │
│    • restart: always → survives reboots     │
└─────────────────────────────────────────────┘
          ▲ Bluetooth PAN
          │
    ┌─────────┐
    │  Phone  │  Browser → http://192.168.50.1:8080
    └─────────┘
```

---

## Files

| File | Purpose |
|---|---|
| `setup_pi.sh` | Run **once** — installs deps, builds Docker image, enables services |
| `bluetooth-pan.service` | systemd unit — manages Bluetooth PAN on the host |
| `dnsmasq_pan.conf` | DHCP config for the `pan0` interface |
| `docker-compose.yml` | Docker service definition for the Flask gallery |
| `Dockerfile` | Python + Flask image |
| `gallery.py` | Flask image gallery source |
| `.env.example` | Template for image folder config (copied to `.env` by setup) |
| `start_server.sh` | Manual/debug fallback — not needed for normal use |

---

## Part 1 — One-time Pi Setup

> Requires keyboard/monitor or SSH access. Only done once.

### 1.1 Copy this folder to the Pi

```bash
scp -r AppInstalacao/ pi@<pi-ip>:~/AppInstalacao/
```

### 1.2 Run the setup script

```bash
cd ~/AppInstalacao
chmod +x setup_pi.sh start_server.sh
sudo ./setup_pi.sh /path/to/your/images/folder
```

**What this does:**
- Installs `bluez-tools` and `dnsmasq`
- Writes your image folder path to `.env` (used by Docker)
- Builds the Docker image
- Installs and enables the `bluetooth-pan` systemd service
- Starts both the Bluetooth PAN service and the Docker container

### 1.3 Pair your phone with the Pi (first time only)

On the Pi, open bluetoothctl:

```bash
sudo bluetoothctl
```

Inside the prompt:

```
power on
agent NoInputNoOutput
default-agent
discoverable on
pairable on
```

On your **phone**: Settings → Bluetooth → scan → tap **raspberrypi**.
Accept the pairing on the phone. Back on the Pi you will see the phone's MAC address appear. Run:

```
trust <PHONE_MAC_ADDRESS>
exit
```

> After `trust`, the phone connects automatically on every subsequent boot — no approval needed on the Pi.

---

## Part 2 — Normal Use (After Setup)

**Turn on the Pi. That's it.**

After ~15 seconds the services are up. On the phone:

### Android
1. Settings → Bluetooth → tap **raspberrypi**
2. Open browser → `http://192.168.50.1:8080`

### iOS
1. Settings → Bluetooth → tap **raspberrypi**
2. Open Safari → `http://192.168.50.1:8080`

---

## Part 3 — Using the Gallery

- Folders are listed at the top — tap to navigate
- Images appear as a thumbnail grid — tap to open full size
- Pinch to zoom on the full image
- Use the **← Back** button to go up a level
- Images are served directly from the Pi (read-only)

---

## Changing the Image Folder

Edit `.env` on the Pi:

```bash
nano ~/AppInstalacao/.env
# change IMAGE_DIR=/new/path
```

Then restart the Docker container:

```bash
cd ~/AppInstalacao
docker compose restart
```

---

## Useful Commands on the Pi

```bash
# Check service status
systemctl status bluetooth-pan
docker compose -f ~/AppInstalacao/docker-compose.yml ps

# View Flask logs
docker logs gallery

# Restart everything
systemctl restart bluetooth-pan
docker compose -f ~/AppInstalacao/docker-compose.yml restart

# Stop everything
systemctl stop bluetooth-pan
docker compose -f ~/AppInstalacao/docker-compose.yml down
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Phone can't find Pi in Bluetooth | `sudo bluetoothctl discoverable on` |
| Browser can't reach `192.168.50.1` | `ip addr show pan0` — must show `192.168.50.1/24` |
| Gallery shows empty page | Check `IMAGE_DIR` in `.env` and restart container |
| `bt-network` not found | `sudo apt install bluez-tools` |
| Container not running | `docker logs gallery` to see the error |
| Phone connects but gets no IP | `sudo systemctl restart dnsmasq` |
| Service fails at boot | `journalctl -u bluetooth-pan -n 50` |
