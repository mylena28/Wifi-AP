# Ideias de implementação

Melhorias planejadas para o wifi_manager, em ordem de prioridade.
Status: itens 1-4 implementados em 2026-07-10 (aguardando validação em
hardware antes de ir para produção); item 5 segue adiado.

## 1. Tempos configuráveis via backup.conf — IMPLEMENTADO (2026-07-10)

Hoje `AP_TIMEOUT`, `CHECK_AP_INTERVAL` e `CHECK_WIFI_INTERVAL` são constantes
fixas no topo do `wifi_manager.sh` — mudar qualquer intervalo exige editar o
script, copiar para `/usr/local/bin` e reiniciar o serviço.

**Proposta:** fazer o script dar `source` no `/etc/wifi_manager/backup.conf`
também na inicialização (hoje só faz ao entrar no modo cliente). Assim qualquer
tempo pode ser ajustado no conf, igual já funciona com `BACKUP_INTERVAL`.

## 2. Auto-atualização do próprio Wifi-AP — IMPLEMENTADO (2026-07-10)

O problema de 2026-07-08: o repositório foi atualizado mas o script instalado
em `/usr/local/bin` ficou na versão antiga (sem o gatilho de backup), e o sync
automático nunca disparava. Isso vai se repetir a cada mudança no projeto.

**Proposta:** o `update_models.sh` já faz `git pull` dos projetos monitorados.
Adicionar o repositório `/mnt/nvme/Wifi-AP` a esse fluxo: quando houver commit
novo, reinstalar os scripts em `/usr/local/bin` (e agendar restart do serviço
num momento seguro, fora do modo AP com clientes).

Implementado em `update_wifi_ap()` (fluxo separado do array `PROJECTS`, já
que também reinstala scripts e reinicia o serviço). Requer migrar o deploy no
Pi de `rsync` manual para `git clone` em `/mnt/nvme/Wifi-AP` — ver seção
"Atualizar o código no Pi" do README. Ainda não validado em hardware.

## 3. Retry mais rápido quando o sync falha — IMPLEMENTADO (2026-07-10)

Se o rsync falha (queda momentânea de rede, host indisponível), a próxima
tentativa só acontece no intervalo cheio (`BACKUP_INTERVAL`, hoje 900s).

**Proposta:** em caso de falha, tentar de novo após 1–2 min, com um limite de
tentativas antes de voltar ao intervalo normal.

## 4. Arquivo de status do último sync — IMPLEMENTADO (2026-07-10)

Para saber de relance se o backup está em dia, sem precisar ler o log.

**Proposta:** o `sync_backup.sh` grava um arquivo simples (ex.:
`/var/lib/wifi_manager/last_sync`) com data/hora e resultado do último sync.
Opcionalmente expor essa informação na galeria web.

Implementado apenas o arquivo de status (`SUCCESS`/`FAILED` + timestamp).
Exposição na galeria web (`gallery.py`) fica para depois, por decisão da
usuária.

## 5. Rotação e limpeza do log — DEIXADO PARA DEPOIS

O `/var/log/wifi_manager.log` cresce sem limite e já contém conteúdo binário
(saída crua do rsync com retornos de carro), o que quebra o `grep`.

**Proposta (adiada por decisão em 2026-07-08):** trocar a saída do rsync por
`--info=stats1`, adicionar config de logrotate e avaliar limpeza de logs
antigos após envio.
