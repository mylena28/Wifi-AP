# AppInstalacao — Wi-Fi Manager + Flask Image Gallery + Backup

Acesse imagens do Raspberry Pi 5 pelo celular via Wi-Fi direto (modo AP).
Quando disponível, o Pi conecta automaticamente a uma rede Wi-Fi conhecida — e sincroniza as imagens com um Pi de backup via rsync.

---

## Comportamento automático

O `wifi_manager` gerencia o Wi-Fi sem intervenção manual:

```
Boot
  │
  ▼
┌──────────────────────────────────────────────────────┐
│  MODO AP — "PiGaleria" @ 192.168.50.1:8080           │
│  Aguarda clientes por 15 min                         │
│  · Alguém conecta → pausa o timer                    │
│  · Último cliente sai → vai para scan imediato       │
│  · 15 min sem ninguém → vai para scan                │
└───────────────────────────┬──────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────┐◄──────────┐
│  WIFI SCAN                                           │           │
│  1. Tenta perfis salvos no NetworkManager            │           │
│  2. Tenta redes do /etc/wifi_manager/networks.conf   │           │
│  · Conectou → WIFI CLIENT                            │           │
│  · Nada encontrado → volta ao AP (ciclo) ────────────┼───────────┘
└───────────────────────────┬──────────────────────────┘
                            │ conectou
                            ▼
┌──────────────────────────────────────────────────────┐
│  WIFI CLIENT                                         │
│  Sistema inteiro tem acesso à internet               │
│  Checa conexão a cada 60s                            │
│  · Ao conectar → dispara rsync para Pi backup        │
│  · A cada 1h → rsync novamente                       │
│  · Perdeu conexão → WIFI SCAN (não volta ao AP)      │
└──────────────────────────────────────────────────────┘
```

> No modo AP a galeria está disponível em `http://192.168.50.1:8080`.
> No modo cliente Wi-Fi o objetivo é internet + backup — a galeria não precisa estar acessível.

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────┐
│                  Raspberry Pi (campo)                    │
│                                                          │
│  [systemd: wifi-manager.service]                         │
│    • wifi_manager.sh — máquina de estados                │
│    • Modo AP: hostapd + dnsmasq + iptables               │
│    • Modo cliente: NetworkManager (nmcli)                │
│    • Lê redes de /etc/wifi_manager/networks.conf         │
│    • Ao conectar: dispara sync_backup.sh em background   │
│                                                          │
│  [Docker: gallery]                                       │
│    • Flask gallery na porta 8080                         │
│    • Monta pasta de imagens (read-only)                  │
│    • Monta /etc/wifi_manager (leitura e escrita)         │
│    • restart: always → sobrevive reboots                 │
└──────────────────────────────────────────────────────────┘
     ▲ Wi-Fi AP              ▲ Wi-Fi cliente (internet)
     │                       │
┌──────────┐         ┌───────────────────────┐
│  Celular  │         │  Raspberry Pi backup  │
│  :8080    │         │  rsync ← imagens      │
└──────────┘         │  IP fixo              │
  /redes             └───────────────────────┘
```

---

## Arquivos

| Arquivo | Função |
|---|---|
| `setup_pi.sh` | Roda **uma vez** — instala dependências, build Docker, ativa serviços |
| `wifi_manager.sh` | Script principal — máquina de estados AP / WiFi scan / cliente |
| `wifi-manager.service` | Serviço systemd do gerenciador Wi-Fi (sobe no boot) |
| `sync_backup.sh` | Executa rsync para o Pi backup via SSH |
| `networks.conf` | Template de redes conhecidas (instalado em `/etc/wifi_manager/`) |
| `backup.conf` | Template de configuração do backup (instalado em `/etc/wifi_manager/`) |
| `hostapd.conf` | Configuração do AP Wi-Fi (SSID, senha, canal) |
| `dnsmasq_wifi.conf` | DHCP para a interface `wlan0` no modo AP |
| `docker-compose.yml` | Definição do serviço Docker da galeria |
| `Dockerfile` | Imagem Python + Flask |
| `gallery.py` | Galeria Flask + página `/redes` para gerenciar redes |
| `.env.example` | Template da pasta de imagens (copiado para `.env` pelo setup) |

---

## Parte 1 — Configuração inicial do Pi

> Requer teclado/monitor ou acesso SSH. Feito apenas uma vez.

### 1.1 Copiar a pasta para o Pi

```bash
scp -r AppInstalacao/ pi@<ip-do-pi>:~/AppInstalacao/
```

### 1.2 Rodar o script de setup

```bash
cd ~/AppInstalacao
chmod +x setup_pi.sh wifi_manager.sh
sudo ./setup_pi.sh /caminho/para/sua/pasta/de/imagens
```

**O que esse script faz:**
- Remove serviços antigos (Bluetooth PAN, wifi-ap)
- Instala `hostapd` e `dnsmasq`
- Salva o caminho das imagens no `.env`
- Faz o build da imagem Docker
- Instala `wifi_manager.sh` e `sync_backup.sh` em `/usr/local/bin/`
- Cria `/etc/wifi_manager/networks.conf` e `backup.conf` (se não existirem)
- Gera chave SSH para rsync sem senha (`/root/.ssh/wifi_manager_backup`)
- Ativa `wifi-manager.service` e `docker` no boot
- Sobe o container e inicia o gerenciador Wi-Fi

---

## Parte 2 — Uso normal (após o setup)

**Ligue o Pi. Só isso.**

O Pi sobe no modo AP por padrão. No celular:

1. Wi-Fi → conectar em **PiGaleria** (senha: `piimagens`)
2. Abrir o navegador → `http://192.168.50.1:8080`

> O Android pode exibir "Sem acesso à internet" — isso é esperado no modo AP. Toque em **Permanecer conectado**.

---

## Parte 3 — Usando a galeria

- Pastas aparecem no topo — toque para navegar entre elas
- Imagens aparecem em grade de miniaturas — toque para abrir em tamanho completo
- Use o botão **← Voltar** para subir um nível
- As imagens são servidas diretamente do Pi (somente leitura)

---

## Parte 4 — Gerenciar redes Wi-Fi salvas

### Pelo browser (recomendado)

Conecte no AP `PiGaleria` e acesse `http://192.168.50.1:8080/redes`

O link **⚙ redes wi-fi** também aparece no canto superior direito da galeria quando você está no AP.

Na página você pode:
- Ver todas as redes cadastradas
- Adicionar uma nova rede (SSID + senha)
- Remover uma rede

> A página só funciona quando conectado ao AP. Fora do AP retorna 403.

### Diretamente no arquivo

```bash
sudo nano /etc/wifi_manager/networks.conf
```

Formato:
```
# Comentários começam com #
MinhaRedeCasa=minhasenha123
RedeDoTrabalho=outrasenha
RedeAberta=
```

As alterações são lidas na próxima vez que o gerenciador entrar no estado de scan.

---

## Parte 5 — Backup automático para Pi externo

Quando o Pi de campo se conecta à internet, ele sincroniza automaticamente a pasta de imagens com um Pi de backup via rsync.

- Só adiciona e atualiza arquivos — **nunca deleta** nada do backup
- Roda ao conectar e a cada 1 hora enquanto conectado
- Se o Pi backup estiver offline, o sync é ignorado e tentado novamente no próximo intervalo

### 5.1 Configurar o backup

Edite o arquivo no Pi de campo:

```bash
sudo nano /etc/wifi_manager/backup.conf
```

```
BACKUP_HOST=192.168.x.x   # IP fixo do Pi backup
BACKUP_USER=pi             # usuário SSH no Pi backup
BACKUP_PATH=/home/pi/backup
BACKUP_INTERVAL=3600       # intervalo em segundos (3600 = 1h)
```

### 5.2 Autorizar acesso SSH (passo manual único)

O `setup_pi.sh` já gerou uma chave SSH em `/root/.ssh/wifi_manager_backup`.
Rode este comando **uma vez** para autorizar o Pi de campo no Pi backup:

```bash
ssh-copy-id -i /root/.ssh/wifi_manager_backup.pub pi@<ip-do-backup>
```

Após isso o rsync funciona automaticamente, sem digitar senha.

### 5.3 Testar manualmente

```bash
sudo /usr/local/bin/sync_backup.sh
```

---

## Alterar a pasta de imagens

```bash
nano ~/AppInstalacao/.env
# altere IMAGE_DIR=/novo/caminho

cd ~/AppInstalacao
docker compose restart
```

---

## Alterar SSID ou senha do AP

```bash
sudo nano /etc/hostapd/hostapd.conf
# altere ssid= e wpa_passphrase=

sudo systemctl restart wifi-manager
```

---

## Comandos úteis no Pi

```bash
# Acompanhar o gerenciador em tempo real
journalctl -fu wifi-manager.service

# Status geral
systemctl status wifi-manager
docker compose -f ~/AppInstalacao/docker-compose.yml ps

# Logs do container Flask
docker logs gallery

# Forçar reinício do gerenciador Wi-Fi
sudo systemctl restart wifi-manager

# Forçar reinício do container
docker compose -f ~/AppInstalacao/docker-compose.yml restart

# Ver clientes conectados ao AP
iw dev wlan0 station dump

# Ver rede Wi-Fi atual (modo cliente)
nmcli device show wlan0
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Celular não vê a rede "PiGaleria" | `journalctl -u wifi-manager -n 50` — verificar se hostapd iniciou |
| Browser não alcança `192.168.50.1` | `ip addr show wlan0` — deve mostrar `192.168.50.1/24` |
| Celular conecta mas não recebe IP | `sudo systemctl restart dnsmasq` |
| Pi não conecta ao Wi-Fi conhecido | Verificar `/etc/wifi_manager/networks.conf` — SSID e senha corretos? |
| Pi ficou preso em WIFI_SCAN | `sudo systemctl restart wifi-manager` para reiniciar o ciclo |
| Galeria abre vazia | Verificar `IMAGE_DIR` no `.env` e reiniciar o container |
| Página `/redes` retorna 403 | Você não está conectado ao AP — essa página só funciona via PiGaleria |
| Container não inicia | `docker logs gallery` para ver o erro |
| Serviço não sobe no boot | `journalctl -u wifi-manager -n 50` |
| Backup não roda | Verificar `BACKUP_HOST` em `/etc/wifi_manager/backup.conf` |
| Erro de permissão no rsync | Rodar `ssh-copy-id -i /root/.ssh/wifi_manager_backup.pub pi@<ip>` no Pi backup |
| Testar sync manualmente | `sudo /usr/local/bin/sync_backup.sh` e ver `/var/log/wifi_manager.log` |
