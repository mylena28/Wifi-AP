# Testes manuais — validar antes de dar merge nesta branch

Checklist para rodar no Raspberry Pi 5 real antes de mesclar
`feature/backup-retry-status-e-autoupdate` em `main`. Nenhuma dessas mudanças
é testável fora do hardware (dependem de `systemctl`, `nmcli`, `docker`,
`hostapd` reais) — ver `CLAUDE.md`.

Marque cada item ao validar. Se algo falhar, anote o comportamento observado
antes de corrigir.

---

## 0. Preparação

- [ ] Fazer backup/anotar o estado atual do Pi antes de testar (branch atual
      em produção, conteúdo de `/etc/wifi_manager/backup.conf`) — caso
      precise reverter.
- [ ] `bash -n wifi_manager.sh sync_backup.sh update_models.sh` local — já
      validado no desenvolvimento, repetir no Pi por garantia.

---

## 1. Tempos configuráveis via `backup.conf` na inicialização

- [ ] Sem editar `backup.conf` (linhas novas continuam comentadas): reiniciar
      `wifi-manager.service` e confirmar nos logs
      (`journalctl -fu wifi-manager.service`) que o comportamento padrão se
      mantém (AP aguarda 15 min sem clientes antes de ir para scan).
- [ ] Descomentar `CHECK_AP_INTERVAL=5` e `AP_TIMEOUT=30` em
      `/etc/wifi_manager/backup.conf`, reiniciar o serviço, e confirmar que o
      AP vai para `WIFI_SCAN` em ~30s sem clientes (bem mais rápido que os 15
      min padrão) — prova que o `source` do conf no boot está funcionando.
- [ ] Restaurar os valores comentados/padrão depois do teste.
- [ ] Confirmar que `BACKUP_INTERVAL` continua sendo recarregado a cada vez
      que entra em `WIFI_CLIENT` (comportamento antigo, não deve ter
      regressão).

---

## 2. Auto-atualização do próprio Wifi-AP

**Este é o item de maior risco — testar com atenção antes de confiar no
ciclo automático em produção.**

- [ ] Clonar o repo em `/mnt/nvme/Wifi-AP` (`git clone
      git@github.com:mylena28/Wifi-AP.git /mnt/nvme/Wifi-AP`) — ou renomear
      o `/mnt/nvme/AppInstalacao` existente para virar esse clone, se for o
      caso.
- [ ] Rodar `sudo ./setup_pi.sh <pasta-de-imagens>` a partir do novo path e
      confirmar que o setup completa sem erros.
- [ ] Com o Pi já rodando a partir do clone, fazer um commit de teste
      (ex.: editar um comentário) e dar push para `origin/main` — **ou**,
      para não mexer em `main` de verdade, mesclar esta própria branch de
      teste localmente no Pi antes de reiniciar o teste, garantindo que
      `origin/main` tenha um commit à frente do que está checked out no Pi.
- [ ] Rodar `sudo /usr/local/bin/update_models.sh` manualmente e conferir nos
      logs (`journalctl -fu wifi-manager.service | grep update` ou saída
      direta do comando):
  - [ ] Detecta o commit novo (`git fetch` + `rev-parse` diferentes).
  - [ ] `git pull origin main` completa sem conflito.
  - [ ] Os 3 scripts são copiados para `/usr/local/bin/` e ficam executáveis
        (`ls -l /usr/local/bin/wifi_manager.sh` etc.).
  - [ ] `docker compose build` e `docker compose up -d` rodam e o container
        `gallery` continua saudável (`docker ps`, `docker logs gallery`).
  - [ ] O `wifi-manager.service` reinicia (`systemctl status
        wifi-manager.service` mostra novo horário de start) e volta a rodar
        sem erro — sem precisar de intervenção manual.
- [ ] Rodar `sudo /usr/local/bin/update_models.sh` de novo sem commits novos
      e confirmar que loga "já está na versão mais recente" e não reinicia
      nada.
- [ ] Confirmar que o restart automático só acontece quando o Pi está em modo
      cliente Wi-Fi — ou seja, que rodar o update enquanto alguém está
      conectado ao AP (`PiGaleria`) navegando na galeria não derruba a sessão
      dele. Na prática isso é garantido pela própria estrutura do
      `wifi_manager.sh` (update só dispara em `WIFI_CLIENT`), mas vale
      confirmar observando o estado no momento do teste.
- [ ] Apagar/renomear temporariamente `/mnt/nvme/Wifi-AP` e rodar
      `update_models.sh` — confirmar que loga "repo não encontrado —
      pulando" e que os projetos `DrowsyDriving`/`FATIGUE` continuam sendo
      processados normalmente (a falha do Wifi-AP não deve interromper o
      restante do script).

---

## 3. Retry mais rápido quando o sync falha

- [ ] Com `BACKUP_HOST` configurado apontando para um host inalcançável
      (ex.: IP que não responde, ou desligar o Pi de backup temporariamente),
      rodar `sudo /usr/local/bin/sync_backup.sh` manualmente e confirmar nos
      logs:
  - [ ] 3 tentativas de rsync (padrão `SYNC_MAX_RETRIES=3`).
  - [ ] ~90s de espera entre cada tentativa (padrão `SYNC_RETRY_DELAY=90`).
  - [ ] Mensagem final de falha após esgotar as tentativas, script sai com
        código 1.
- [ ] Descomentar `SYNC_MAX_RETRIES=2` e `SYNC_RETRY_DELAY=10` em
      `backup.conf`, repetir o teste acima e confirmar que os novos valores
      são respeitados (2 tentativas, ~10s entre elas).
- [ ] Restaurar o Pi de backup / `BACKUP_HOST` correto e confirmar que o sync
      funciona normalmente na primeira tentativa (sem regressão no caminho
      feliz).
- [ ] Restaurar os valores comentados/padrão em `backup.conf` depois do
      teste.

---

## 4. Arquivo de status do último sync

- [ ] Após um sync bem-sucedido, conferir
      `cat /var/lib/wifi_manager/last_sync` → deve mostrar
      `SUCCESS <data e hora>`.
- [ ] Forçar uma falha (ex.: `BACKUP_HOST` errado) e rodar o sync — conferir
      que o arquivo passa a mostrar `FAILED <data e hora> (N tentativas)`.
- [ ] Confirmar que o arquivo é sobrescrito (não acumula histórico) a cada
      execução, e que o diretório `/var/lib/wifi_manager` é criado
      automaticamente se não existir.

---

## 5. Regressão geral (ciclo completo do wifi_manager)

- [ ] Ciclo AP → WIFI_SCAN → WIFI_CLIENT continua funcionando do zero
      (reboot do Pi longe de qualquer rede conhecida → AP sobe → conectar
      via celular → confirmar galeria acessível em
      `http://192.168.50.1:8080`).
- [ ] `/redes` continua funcionando (adicionar/remover rede) só dentro da
      subnet do AP.
- [ ] Conectar a uma rede Wi-Fi conhecida e confirmar que `sync_backup.sh` e
      `update_models.sh` disparam automaticamente ao conectar (não só
      manualmente).
- [ ] Confirmar que os lock files (`/var/run/sync_backup.lock`,
      `/var/run/update_models.lock`) impedem execuções simultâneas — tentar
      rodar `sync_backup.sh` duas vezes seguidas rapidamente e ver a segunda
      chamada logar "já em andamento".

---

## Depois de validar tudo

- [ ] Todos os itens acima passaram → seguro dar merge desta branch em
      `main`.
- [ ] Algum item falhou → anotar o comportamento e ajustar antes do merge;
      não mesclar com testes pendentes ou reprovados.
