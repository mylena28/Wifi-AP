# Sugestões de implementação

## 1. Porta SSH customizada no backup (`BACKUP_PORT`)

**Quando usar:** o roteador do escritório faz port forwarding em porta diferente da 22 (ex: `2222 → Pi:22`).

**O que mudar:**
- `backup.conf` — adicionar `BACKUP_PORT=22`
- `sync_backup.sh` — passar `-p $BACKUP_PORT` no argumento `-e` do rsync

---

## 2. VPN mesh (Tailscale ou ZeroTier)

**Quando usar:** o escritório não tem IP fixo, ou não é possível configurar port forwarding no roteador.

**Como funciona:** cada Pi roda um container da VPN e recebe um IP virtual fixo. O `BACKUP_HOST` em `backup.conf` passa a ser esse IP virtual.

**Opções:**

| | Tailscale | ZeroTier |
|---|---|---|
| Facilidade | Alta | Média |
| Gratuito (uso pessoal) | Sim | Sim |
| Gratuito (organização) | Não | Não |
| Docker oficial | Sim | Comunidade |

**O que mudar:**
- `docker-compose.yml` — adicionar serviço `tailscale` ou `zerotier`
- `backup.conf` — `BACKUP_HOST` recebe o IP virtual gerado pela VPN
- `setup_pi.sh` — instalar e autenticar o cliente VPN nos dois Pis

---

## 3. Opção escolhida pela equipe

IP fixo do escritório com port forwarding — implementar item **1** quando a porta for definida.
