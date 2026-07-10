# AppInstalacao — Wi-Fi Manager + Flask Image Gallery

Acesse imagens do Raspberry Pi 5 pelo celular via Wi-Fi direto (modo AP).
Quando disponível, o Pi conecta automaticamente a uma rede Wi-Fi conhecida para sincronizar backups e atualizar modelos.

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
│  Ao conectar (e a cada 1h):                          │
│  · sync_backup.sh  — rsync das imagens para Pi backup│
│  · update_models.sh — git pull + docker rebuild dos  │
│    projetos DrowsyDriving e FATIGUE se houver update │
│  Checa conexão a cada 60s                            │
│  · Perdeu conexão → WIFI SCAN (não volta ao AP)      │
└──────────────────────────────────────────────────────┘
```

> No modo AP a galeria está disponível em `http://192.168.50.1:8080`.

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────┐
│                    Raspberry Pi 5                        │
│                                                          │
│  [systemd: wifi-manager.service]                         │
│    • wifi_manager.sh — máquina de estados                │
│    • Modo AP: hostapd + dnsmasq + iptables               │
│    • Modo cliente: NetworkManager (nmcli)                │
│    • Ao conectar: sync backup + update modelos           │
│                                                          │
│  [Docker: gallery]                                       │
│    • Flask gallery na porta 8080                         │
│    • Monta pasta de imagens (read-only)                  │
│    • Monta /etc/wifi_manager (leitura e escrita)         │
│    • restart: always → sobrevive reboots                 │
│                                                          │
│  [/mnt/nvme/DrowsyDriving]  [/mnt/nvme/FATIGUE]        │
│    • Atualizados via git pull quando há internet         │
│    • Container reconstruído automaticamente se mudou     │
└──────────────────────────────────────────────────────────┘
          ▲ Wi-Fi (SSID: PiGaleria)
          │
    ┌──────────┐
    │  Celular  │  Browser → http://192.168.50.1:8080
    └──────────┘          → /redes para gerenciar redes Wi-Fi
```

---

## Arquivos

| Arquivo | Função |
|---|---|
| `setup_pi.sh` | Roda **uma vez** — instala dependências, build Docker, ativa serviços |
| `wifi_manager.sh` | Script principal — máquina de estados AP / WiFi scan / cliente |
| `wifi-manager.service` | Serviço systemd do gerenciador Wi-Fi (sobe no boot) |
| `sync_backup.sh` | Sincroniza imagens com o Pi backup via rsync/SSH |
| `update_models.sh` | Atualiza DrowsyDriving e FATIGUE via git pull + docker |
| `backup.conf` | Configuração do Pi de backup (IP, usuário, caminho, intervalo) |
| `networks.conf` | Template do arquivo de redes conhecidas (instalado em `/etc/wifi_manager/`) |
| `hostapd.conf` | Configuração do AP Wi-Fi (SSID, senha, canal) |
| `dnsmasq_wifi.conf` | DHCP para a interface `wlan0` no modo AP |
| `docker-compose.yml` | Definição do serviço Docker da galeria |
| `Dockerfile` | Imagem Python + Flask |
| `gallery.py` | Galeria Flask + página `/redes` para gerenciar redes |
| `dev_mode.sh` | Para o AP e conecta ao WiFi manualmente (uso em desenvolvimento) |
| `.env.example` | Template da pasta de imagens (copiado para `.env` pelo setup) |

---

## Parte 1 — Configuração inicial do Pi

> Requer teclado/monitor ou acesso SSH. Feito apenas uma vez.

### 1.1 Clonar o repositório no Pi

```bash
git clone git@github.com:mylena28/Wifi-AP.git /mnt/nvme/Wifi-AP
```

> A partir daqui o código no Pi vive nesse clone git — atualizações
> seguintes não precisam mais de `rsync` manual, ver
> [Atualizar o código no Pi](#atualizar-o-código-no-pi).

### 1.2 Rodar o script de setup

```bash
cd /mnt/nvme/Wifi-AP
chmod +x setup_pi.sh wifi_manager.sh dev_mode.sh
sudo ./setup_pi.sh /mnt/nvme/DrowsyDriving/logs
```

**O que esse script faz:**
- Remove serviços antigos (Bluetooth PAN, wifi-ap)
- Instala `hostapd` e `dnsmasq`
- Salva o caminho das imagens no `.env`
- Faz o build da imagem Docker
- Instala `wifi_manager.sh`, `sync_backup.sh` e `update_models.sh` em `/usr/local/bin/`
- Cria `/etc/wifi_manager/networks.conf` e `backup.conf` (se não existirem)
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

## Parte 5 — Sincronização de backup (requer segundo Pi)

> **Pré-requisito:** ter um segundo Raspberry Pi disponível na mesma rede com IP fixo.

Quando conectado ao Wi-Fi, o Pi sincroniza automaticamente a pasta de imagens para o Pi backup via rsync/SSH, sem deletar arquivos no destino.

### 5.1 Configurar o `backup.conf` no Pi principal

```bash
sudo nano /etc/wifi_manager/backup.conf
```

Preencha os campos:
```bash
BACKUP_HOST=192.168.15.XX   # IP ou hostname do Pi backup
BACKUP_PORT=22                # porta SSH no Pi backup (padrão 22)
BACKUP_USER=pi               # usuário SSH no Pi backup
BACKUP_PATH=/home/pi/backup  # pasta destino no Pi backup
BACKUP_INTERVAL=3600         # intervalo entre syncs em segundos (3600 = 1h)
```

### 5.2 Criar a chave SSH sem senha para o rsync

No Pi principal (como root):
```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/wifi_manager_backup -N ""
sudo ssh-copy-id -i /root/.ssh/wifi_manager_backup.pub -p <porta> pi@<ip-do-pi-backup>
```

Teste a conexão:
```bash
sudo ssh -i /root/.ssh/wifi_manager_backup -p <porta> pi@<ip-do-pi-backup> "echo OK"
```

### 5.3 Comportamento

- Ao conectar ao Wi-Fi → sync imediato em background
- A cada `BACKUP_INTERVAL` segundos enquanto conectado → novo sync
- Se o sync já estiver rodando quando o intervalo chegar → chamada ignorada (lock file)
- Se interrompido no meio → retoma de onde parou na próxima execução (`--partial`)
- Se `BACKUP_HOST` estiver vazio → sync silenciosamente ignorado

Acompanhar os logs:
```bash
journalctl -fu wifi-manager.service | grep backup
```

---

## Parte 6 — Atualização automática de modelos

Ao conectar ao Wi-Fi, o Pi verifica se há commits novos nos repositórios dos projetos e atualiza automaticamente se houver.

**Projetos monitorados:**
- `/mnt/nvme/Monitoramento/DrowsyDriving` — branch `main`
- `/mnt/nvme/Monitoramento/FATIGUE` — branch `main`

### Comportamento

- Ao conectar ao Wi-Fi → verificação imediata em background
- A cada 1 hora enquanto conectado → nova verificação
- Se não houver commits novos → loga "já está na versão mais recente" e termina
- Se houver commits novos:
  1. `git pull origin main`
  2. `docker compose build`
  3. `docker compose up -d`

Acompanhar os logs:
```bash
journalctl -fu wifi-manager.service | grep update
```

### Adicionar ou remover projetos monitorados

Edite o array `PROJECTS` em `/usr/local/bin/update_models.sh`:
```bash
PROJECTS=(
    "/mnt/nvme/DrowsyDriving"
    "/mnt/nvme/FATIGUE"
    "/mnt/nvme/OutroProjeto"   # adicione aqui
)
```

> O próprio repositório Wifi-AP (`/mnt/nvme/Wifi-AP`) **não** faz parte desse
> array — ele é atualizado por um fluxo separado dentro do
> `update_models.sh` (ver [Atualizar o código no Pi](#atualizar-o-código-no-pi)),
> porque além de `git pull` + rebuild ele também reinstala os scripts em
> `/usr/local/bin` e reinicia o `wifi-manager.service`.

---

## Desativar o AP e conectar ao Wi-Fi manualmente

Útil para acessar o Pi pela rede local (ex: atualizar código via SSH).

```bash
sudo ./dev_mode.sh SALTE
# ou: sudo ./dev_mode.sh "Nome da Rede"
```

Descubra o IP após conectar:
```bash
hostname -I
```

Para restaurar o AP:
```bash
sudo systemctl start wifi-manager.service
```

---

## Atualizar o código no Pi

**Automático:** ao conectar ao Wi-Fi (e a cada 1h enquanto conectado), o
`update_models.sh` também verifica commits novos em `/mnt/nvme/Wifi-AP`
(clonado no [setup inicial](#11-clonar-o-repositório-no-pi)). Se houver
atualização:
1. `git pull origin main`
2. reinstala `wifi_manager.sh`, `sync_backup.sh` e `update_models.sh` em
   `/usr/local/bin/`
3. `docker compose build && docker compose up -d` (container da galeria)
4. agenda restart do `wifi-manager.service`

Isso só roda enquanto o Pi está em modo cliente Wi-Fi — nunca durante o modo
AP com alguém conectado na galeria. Acompanhar:
```bash
journalctl -fu wifi-manager.service | grep update
```

**Manual** (sem esperar o Pi conectar, ou para forçar uma atualização
imediata — requer SSH, ver
[Desativar o AP e conectar ao Wi-Fi manualmente](#desativar-o-ap-e-conectar-ao-wi-fi-manualmente)):
```bash
cd /mnt/nvme/Wifi-AP
git pull origin main
sudo cp wifi_manager.sh  /usr/local/bin/wifi_manager.sh
sudo cp update_models.sh /usr/local/bin/update_models.sh
sudo cp sync_backup.sh   /usr/local/bin/sync_backup.sh
docker compose build && docker compose up -d
sudo systemctl restart wifi-manager.service
```

---

## Comandos úteis no Pi

```bash
# Acompanhar o gerenciador em tempo real
journalctl -fu wifi-manager.service

# Status geral
systemctl status wifi-manager.service
docker ps

# Logs do container Flask
docker logs gallery

# Forçar reinício do gerenciador Wi-Fi
sudo systemctl restart wifi-manager.service

# Forçar reinício do container
cd /mnt/nvme/Wifi-AP && docker compose restart

# Ver clientes conectados ao AP
iw dev wlan0 station dump

# Ver rede Wi-Fi atual (modo cliente)
nmcli device show wlan0

# Rodar update dos modelos manualmente
sudo /usr/local/bin/update_models.sh

# Rodar sync de backup manualmente
sudo /usr/local/bin/sync_backup.sh
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Celular não vê a rede "PiGaleria" | `journalctl -u wifi-manager -n 50` — verificar se hostapd iniciou |
| Browser não alcança `192.168.50.1` | `ip addr show wlan0` — deve mostrar `192.168.50.1/24` |
| Celular conecta mas não recebe IP | `sudo systemctl restart dnsmasq` |
| Pi não conecta ao Wi-Fi conhecido | Verificar `/etc/wifi_manager/networks.conf` — SSID e senha corretos? |
| Pi ficou preso em WIFI_SCAN | `sudo systemctl restart wifi-manager.service` para reiniciar o ciclo |
| Galeria abre vazia | Verificar `IMAGE_DIR` no `.env` e reiniciar o container |
| Página `/redes` retorna 403 | Você não está conectado ao AP — essa página só funciona via PiGaleria |
| Container não inicia | `docker logs gallery` para ver o erro |
| wlan0 aparece "não disponível" | `sudo nmcli radio wifi on && sudo rfkill unblock all` |
| Wi-Fi não volta após dev_mode.sh | `sudo nmcli radio wifi on` — pode ter sido desativado manualmente |
| Sync não executa | Verificar `BACKUP_HOST` em `/etc/wifi_manager/backup.conf` |
| Update dos modelos não executa | `sudo /usr/local/bin/update_models.sh` para ver o erro manualmente |

---

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).

---

## Agradecimentos

Este projeto é desenvolvido em parceria com:

- **[FAPEG](https://www.fapeg.go.gov.br)** — Fundação de Amparo à Pesquisa do Estado de Goiás
- **IEL/GO** — Instituto Euvaldo Lodi — Núcleo Regional Goiás
- **Salte Tecnologia**

A pesquisa conta com apoio da FAPEG no âmbito do programa *Segurança na Operação de Equipamentos Móveis* (Edital 27/2025).
