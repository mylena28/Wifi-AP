# Diagnóstico Wi-Fi AP — Comandos para rodar no Raspberry Pi

## 1. Verificar status dos serviços

```bash
# Verificar se o serviço wifi-ap está instalado e rodando
systemctl status wifi-ap

# Verificar se o hostapd está rodando
systemctl status hostapd

# Ver se wlan0 tem o IP correto (192.168.50.1)
ip addr show wlan0
```

## 2. Se o wifi-ap.service não estiver instalado

Transferir os arquivos do projeto correto (AppInstalacao, branch wifi-ap) para o Pi:

```bash
# No computador local, dentro de AppInstalacao:
rsync -av --exclude='.git' /home/mylena/Workspace/FAPEG/codigo/AppInstalacao/ raspberrypi5@192.168.15.30:/mnt/nvme/AppInstalacao/
```

Depois no Pi:

```bash
cd /mnt/nvme/AppInstalacao
sudo ./setup_pi.sh /mnt/nvme/DrowsyDriving/logs
```

## 3. Resultado esperado

- Rede Wi-Fi **PiGaleria** visível no celular
- Senha: **piimagens**
- Galeria em: http://192.168.50.1:8080

## Contexto do problema

O setup_pi.sh do repositório `Phone_Rap_bluetooth` (versão antiga Bluetooth) foi rodado
no lugar do setup correto do `AppInstalacao` (branch wifi-ap, versão Wi-Fi AP com hostapd).
O serviço wifi-ap.service e o hostapd provavelmente não estão instalados/ativos no Pi.
