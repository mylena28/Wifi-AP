# AppInstalacao — Wi-Fi AP + Flask Image Gallery

Acesse imagens do Raspberry Pi 5 pelo celular via Wi-Fi direto.
Sem internet, sem roteador. Tudo sobe automaticamente no boot.

---

## Arquitetura

```
┌──────────────────────────────────────────────┐
│              Raspberry Pi 5                  │
│                                              │
│  [systemd: wifi-ap.service]                  │
│    • Configura wlan0 com IP 192.168.50.1     │
│    • Sobe hostapd (AP Wi-Fi "PiGaleria")     │
│    • Sobe dnsmasq (DHCP para o celular)      │
│    • Redireciona porta 80 → 8080 (iptables)  │
│                                              │
│  [Docker: gallery container]                 │
│    • Flask image gallery na porta 8080       │
│    • Monta a pasta de imagens (read-only)    │
│    • restart: always → sobrevive reboots     │
└──────────────────────────────────────────────┘
          ▲ Wi-Fi (SSID: PiGaleria)
          │
    ┌─────────┐
    │  Celular │  Browser → http://192.168.50.1:8080
    └─────────┘
```

---

## Arquivos

| Arquivo | Função |
|---|---|
| `setup_pi.sh` | Roda **uma vez** — instala dependências, build Docker, ativa serviços |
| `wifi-ap.service` | Serviço systemd — gerencia o AP Wi-Fi e o roteamento |
| `hostapd.conf` | Configuração do AP Wi-Fi (SSID, senha, canal) |
| `dnsmasq_wifi.conf` | DHCP para a interface `wlan0` |
| `docker-compose.yml` | Definição do serviço Docker da galeria |
| `Dockerfile` | Imagem Python + Flask |
| `gallery.py` | Código-fonte da galeria Flask |
| `.env.example` | Template da pasta de imagens (copiado para `.env` pelo setup) |
| `start_server.sh` | Start manual para debug — não necessário no uso normal |

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
chmod +x setup_pi.sh start_server.sh
sudo ./setup_pi.sh /caminho/para/sua/pasta/de/imagens
```

**O que esse script faz:**
- Instala `hostapd` e `dnsmasq`
- Salva o caminho das imagens no `.env` (usado pelo Docker)
- Faz o build da imagem Docker
- Instala e ativa o serviço `wifi-ap.service`
- Sobe o AP Wi-Fi e o container Docker

---

## Parte 2 — Uso normal (após o setup)

**Ligue o Pi. Só isso.**

Após ~15 segundos os serviços sobem. No celular:

### Android e iOS
1. Wi-Fi → conectar na rede **PiGaleria** (senha: `piimagens`)
2. Abrir o navegador → `http://192.168.50.1:8080`

> O Android pode exibir "Sem acesso à internet" ao conectar — isso é esperado e não impede o uso. Toque em "Permanecer conectado" se aparecer.

---

## Parte 3 — Usando a galeria

- Pastas aparecem no topo — toque para navegar
- Imagens aparecem em grade de miniaturas — toque para abrir em tamanho completo
- Belisque para dar zoom na imagem
- Use o botão **← Voltar** para subir um nível
- As imagens são servidas diretamente do Pi (somente leitura)

---

## Alterar a pasta de imagens

Edite `.env` no Pi:

```bash
nano ~/AppInstalacao/.env
# altere IMAGE_DIR=/novo/caminho
```

Reinicie o container:

```bash
cd ~/AppInstalacao
docker compose restart
```

---

## Alterar SSID ou senha do Wi-Fi

Edite `hostapd.conf` no Pi:

```bash
sudo nano /etc/hostapd/hostapd.conf
# altere ssid= e wpa_passphrase=
```

Reinicie o serviço:

```bash
sudo systemctl restart wifi-ap
```

---

## Comandos úteis no Pi

```bash
# Status dos serviços
systemctl status wifi-ap
docker compose -f ~/AppInstalacao/docker-compose.yml ps

# Logs do Flask
docker logs gallery

# Reiniciar tudo
sudo systemctl restart wifi-ap
docker compose -f ~/AppInstalacao/docker-compose.yml restart

# Parar tudo
sudo systemctl stop wifi-ap
docker compose -f ~/AppInstalacao/docker-compose.yml down
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Celular não vê a rede Wi-Fi | `sudo systemctl status wifi-ap` — verificar se hostapd iniciou |
| Browser não alcança `192.168.50.1` | `ip addr show wlan0` — deve mostrar `192.168.50.1/24` |
| Celular conecta mas não recebe IP | `sudo systemctl restart dnsmasq` |
| Galeria abre vazia | Verificar `IMAGE_DIR` no `.env` e reiniciar o container |
| Container não está rodando | `docker logs gallery` para ver o erro |
| Serviço falha no boot | `journalctl -u wifi-ap -n 50` |
| hostapd não encontrado | `sudo apt install hostapd` |
