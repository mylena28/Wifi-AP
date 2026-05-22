# Status do Projeto — AppInstalacao (Bluetooth PAN + Flask Gallery)

**Última atualização:** 2026-05-20  
**Objetivo:** Acessar imagens do Raspberry Pi 5 pelo celular via Bluetooth, sem internet/Wi-Fi.

---

## O que está funcionando

| Componente | Status |
|---|---|
| `bluetooth-pan.service` | Rodando — `bt-network NAP server registered` |
| `pan0` interface | UP, IP `192.168.50.1/24` |
| `bnep0` (conexão BT do celular) | Sendo criado e bridgeado no `pan0` quando "Internet access" ativado |
| Docker `gallery` container | Rodando — Flask respondendo em `0.0.0.0:8080` |
| Flask acessível do próprio Pi | Sim — `curl http://192.168.50.1:8080` retorna HTML |

---

## Problema atual — celular não recebe IP via DHCP

- `dnsmasq` está rodando mas o arquivo `/var/lib/misc/dnsmasq.leases` permanece vazio
- `bnep0` aparece na bridge mas `tcpdump -i any port 67 or port 68` não captura nenhum pacote DHCP
- O celular ativa "Internet access" no Bluetooth mas o browser não consegue acessar `http://192.168.50.1:8080`

---

## Hipóteses ainda não descartadas

1. **Android não manda DHCP request automaticamente** — o `bnep0` é criado mas o celular pode estar esperando algo antes de solicitar IP
2. **Filtro na bridge** — `br_netfilter` pode estar bloqueando pacotes antes de chegarem ao dnsmasq (verificar `cat /proc/sys/net/bridge/bridge-nf-call-iptables`)
3. **dnsmasq não está respondendo ao range correto** — config atual sem `listen-address`, só `interface=pan0`

---

## Próximas coisas a tentar

1. `sudo tcpdump -i bnep0 -n` — ver se QUALQUER tráfego chega no bnep0 (sem filtro de porta)
2. `ip neigh show dev pan0` — ver se o celular aparece na tabela ARP (teria IP link-local)
3. `cat /proc/sys/net/bridge/bridge-nf-call-iptables` — se for `1`, adicionar regra para permitir DHCP na bridge
4. Testar atribuir IP estático manualmente ao celular via `adb`:
   ```bash
   adb shell ip addr add 192.168.50.2/24 dev bnep0
   ```
5. Considerar trocar dnsmasq por `udhcpd` (mais simples para interfaces específicas)

---

## Arquivos relevantes no Pi

- Pasta do projeto: `~/video/PhoneRasp/`
- Serviço BT: `/etc/systemd/system/bluetooth-pan.service`
- Config DHCP: `/etc/dnsmasq.d/bluetooth-pan.conf`
- Docker: `~/video/PhoneRasp/docker-compose.yml`

## Config atual do dnsmasq no Pi (`/etc/dnsmasq.d/bluetooth-pan.conf`)

```
interface=pan0
bind-interfaces
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
dhcp-option=3,192.168.50.1
```

---

## MAC do celular

`EC:ED:73:7A:47:31`
