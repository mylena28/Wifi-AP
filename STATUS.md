# Status do Projeto — AppInstalacao (Bluetooth PAN + Flask Gallery)

**Última atualização:** 2026-06-12  
**Objetivo:** Acessar imagens do Raspberry Pi 5 pelo celular via Bluetooth, sem internet/Wi-Fi.

---

## O que está funcionando (confirmado em 2026-05-27)

| Componente | Status |
|---|---|
| `bluetooth-pan.service` | Rodando com configs novas |
| `pan0` interface | UP, IP `192.168.50.1/24` + IPv6 `fd00::1/64` |
| `bnep0` (conexão BT do celular) | Criado e bridgeado no `pan0` quando "Acesso à internet" ativado |
| Docker `gallery` container | Rodando — Flask em `[::]:8080` (IPv4 + IPv6) |
| Flask acessível do Pi via IPv4 | `curl http://192.168.50.1:8080` retorna HTML |
| Flask acessível do Pi via IPv6 | `curl -6 http://[fd00::1]:8080` retorna HTML |
| dnsmasq enviando Router Advertisements | Confirmado — celular recebe RA e configura `fd00::eeed:73ff:fe7a:4731` via SLAAC |

---

## Causa raiz identificada — Docker bloqueando ip6tables/iptables

O Docker (rodando em `network_mode: host`) seta a policy `DROP` no chain `FORWARD` do
`ip6tables` e do `iptables`, e adiciona uma regra `DROP` catch-all no final da chain. Como
resultado, pacotes vindos do celular via `pan0` são descartados antes de chegar ao Flask.

O `sysctl bridge-nf-call-ip6tables=0` do serviço não é suficiente quando o Docker sobe depois
e reabilita o `br_netfilter` ou adiciona suas próprias regras.

### Correção aplicada (2026-06-12)

Adicionadas regras `ACCEPT` explícitas para `pan0` no início das chains INPUT e FORWARD,
tanto no `bluetooth-pan.service` quanto no `start_server.sh`:

```
ip6tables -I INPUT  -i pan0 -j ACCEPT
ip6tables -I FORWARD -i pan0 -j ACCEPT
iptables  -I INPUT  -i pan0 -j ACCEPT
iptables  -I FORWARD -i pan0 -j ACCEPT
```

Inserir no topo (`-I`) garante que a regra ACCEPT fica antes de qualquer DROP do Docker,
que é sempre adicionado com `-A` (append, no final).

As regras são removidas no `ExecStop` / `cleanup()`.

---

## Próximo passo — aplicar no Pi e testar

```bash
# No diretório do projeto no Pi:
sudo cp bluetooth-pan.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart bluetooth-pan.service

# Conectar celular → "Acesso à internet" → abrir no browser:
#   http://192.168.50.1:8080   (IPv4 — mais simples de digitar)
#   http://[fd00::1]:8080      (IPv6)
```

Se ainda não funcionar, verificar o estado das chains:
```bash
sudo ip6tables -L INPUT  -n --line-numbers
sudo ip6tables -L FORWARD -n --line-numbers
sudo iptables  -L INPUT  -n --line-numbers
sudo iptables  -L FORWARD -n --line-numbers
```

---

## Arquivos relevantes

| Arquivo | Localização no Pi |
|---|---|
| Serviço BT | `/etc/systemd/system/bluetooth-pan.service` |
| Config dnsmasq | `/etc/dnsmasq.d/bluetooth-pan.conf` |
| Docker | `~/video/PhoneRasp/docker-compose.yml` |
| Script de diagnóstico | `~/video/PhoneRasp/fix_dnsmasq.sh` |

---

## Config atual do dnsmasq no Pi (`/etc/dnsmasq.d/bluetooth-pan.conf`)

```
interface=pan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-authoritative
dhcp-broadcast
dhcp-range=::1,::ffff,constructor:pan0,ra-only,64,24h
```

---

## MAC do celular

`EC:ED:73:7A:47:31`  
IPv6 SLAAC configurado: `fd00::eeed:73ff:fe7a:4731`
