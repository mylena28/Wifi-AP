# Wifi-AP — guia de trabalho

Wi-Fi Manager + galeria Flask para Raspberry Pi 5. Ver `README.md` para
arquitetura, fluxo de estados e guia de uso completo. Este arquivo guarda
convenções de código e decisões de projeto que não estão no README.

## Ambiente de execução

- Roda em produção **dentro do Raspberry Pi 5**, não no host de
  desenvolvimento. Scripts shell (`wifi_manager.sh`, `sync_backup.sh`,
  `update_models.sh`) manipulam `wlan0`, `hostapd`, `NetworkManager`,
  `iptables` — não são testáveis fora do Pi real. Ao propor mudanças
  nesses arquivos, ser explícito sobre o que exigiria teste manual no
  hardware antes de ir para produção.
- A galeria (`gallery.py`) roda em container Docker
  (`network_mode: host`, porta 8080); os scripts de gerenciamento de
  Wi-Fi rodam direto no host do Pi via `systemd`
  (`wifi-manager.service`), fora do Docker — não misturar as duas
  camadas ao propor mudanças.
- Arquivos instalados em `/usr/local/bin/` (`wifi_manager.sh`,
  `sync_backup.sh`, `update_models.sh`) e `/etc/wifi_manager/`
  (`networks.conf`, `backup.conf`, `rsync_filter.conf`, `.env`) são
  **cópias** do repo — editar sempre o arquivo no repo e reinstalar (ver
  seção "Atualizar o código no Pi" do README), nunca editar a cópia
  instalada diretamente.
- `PROJECTS` em `update_models.sh` está fixo em
  `/mnt/nvme/Monitoramento/DrowsyDriving` e
  `/mnt/nvme/Monitoramento/FATIGUE` — mudou de `/mnt/nvme/<Projeto>` para
  esse layout (commit `cfd6740`); não reverter sem confirmar com o
  usuário que o path mudou de novo.
- `IMAGE_DIR` (`.env`) é `/mnt/nvme/Monitoramento` inteiro — tudo dentro
  dessa pasta (incluindo os repos `DrowsyDriving`/`FATIGUE` acima) é
  montado read-only na galeria; não é um subdiretório tipo
  `.../DrowsyDriving/logs`. `Wifi-AP` fica **fora** dessa árvore, como
  irmão dela: `/mnt/nvme/Wifi-AP`, não `/mnt/nvme/Monitoramento/Wifi-AP`.
- O que a galeria mostra (tudo em `IMAGE_DIR`) e o que o `sync_backup.sh`
  envia pro Pi backup são coisas diferentes: o rsync usa
  `rsync_filter.conf` (`/etc/wifi_manager/rsync_filter.conf`) pra mandar
  só a subpasta `logs/` de cada projeto, ignorando `.py` e `.git/` — a
  galeria não usa esse filtro, continua servindo `IMAGE_DIR` inteiro.

## Code style — shell (`*.sh`)

- `log()` local por script, prefixo de contexto quando não é o
  `wifi_manager.sh` principal (ex.: `[backup]`, `[update]`), sempre
  gravando em `/var/log/wifi_manager.log` com `tee -a`.
- Funções privadas/helpers prefixadas com `_` (ex.: `_start_ap`,
  `_try_networks_file`) — segue o padrão já usado em `wifi_manager.sh`.
- Todo comando que pode falhar sem que isso seja um erro real leva
  `2>/dev/null || true` (ex.: `rfkill`, `nmcli`, `ip link`) — falha
  silenciosa é aceitável para comandos idempotentes/best-effort, não para
  o comando principal do script.
- Scripts que rodam em background via `wifi_manager.sh`
  (`sync_backup.sh`, `update_models.sh`) usam lock file em `/var/run/` +
  `trap "rm -f $LOCK" EXIT` para impedir execuções simultâneas — seguir
  esse padrão para qualquer novo script disparado em background.
- Comentários e mensagens de log em português; nomes de variáveis e
  funções em inglês/neutro (`log`, `state`, `transition_to`).
- Sem `set -e` em `wifi_manager.sh`/`sync_backup.sh`/`update_models.sh`
  (são loops de longa duração que precisam sobreviver a falhas
  pontuais); `setup_pi.sh` usa `set -e` porque é script de instalação
  linear que deve abortar no primeiro erro.

## Code style — Python (`gallery.py`)

- Flask puro, sem framework de templates — HTML inline em strings
  (`HTML_HEAD`, `REDES_HEAD`) concatenadas com f-strings. Seguir esse
  padrão em vez de introduzir Jinja/templates separados.
- Toda rota que só deve funcionar dentro do AP usa o decorator
  `_only_ap` (checa `request.remote_addr.startswith(AP_SUBNET)`) —
  aplicar a qualquer nova rota sensível (config, credenciais).
- `_read_networks`/`_write_networks` são a única forma de tocar
  `networks.conf` a partir do Python — não duplicar o parsing em outro
  lugar.

## Segurança

- `networks.conf` guarda senhas de Wi-Fi em texto puro — é o formato já
  usado pelo `wifi_manager.sh` (bash não tem parser de config seguro sem
  dependência extra); não expor esse arquivo por rota fora do `_only_ap`.
- Toda rota de escrita (`/redes/adicionar`, `/redes/remover`) exige estar
  na subnet do AP (`192.168.50.0/24`) — nunca remover essa checagem para
  "simplificar" testes.
- Chave SSH do backup (`/root/.ssh/wifi_manager_backup`) é gerada sem
  senha (`-N ""`) propositalmente, para automação sem interação — não é
  descuido, é o modelo de autenticação do rsync automático.
- `.env`, `backup.conf` preenchido e chaves SSH nunca são commitados.

## Estrutura

- `wifi_manager.sh` — máquina de estados principal (AP / WIFI_SCAN /
  WIFI_CLIENT), dispara os outros dois scripts em background.
- `sync_backup.sh`, `update_models.sh` — tarefas independentes chamadas
  pelo `wifi_manager.sh` ao conectar e periodicamente; também podem ser
  rodados manualmente para debug.
- `gallery.py` + `Dockerfile` + `docker-compose.yml` — único componente
  que roda em container.
- `setup_pi.sh` — instalação, roda uma vez por Pi; idempotente por
  design (checa antes de sobrescrever `networks.conf`/`backup.conf`
  existentes).
- `dev_mode.sh` — atalho de desenvolvimento para tirar o Pi do modo AP
  e conectar num Wi-Fi normal via SSH.
- `IDEIAS.md` / `SUGESTOES.md` — propostas e decisões de escopo ainda não
  implementadas; consultar antes de sugerir uma feature nova para
  verificar se já foi considerada (e por quê foi aceita/adiada).

## Git

- Commits diretos e descritivos, prefixo `fix:`/`add:`/`docs:` quando
  aplicável (não é regra rígida no histórico, mas é o padrão mais comum
  — seguir quando fizer sentido).
- Mensagem do commit curta e concisa — poucas palavras, separadas por `-`
  (ex.: `add: retry-sync-backup`, `fix: timeout-ap-configuravel`).
- Nunca commitar sem pedido explícito do usuário.
- Nunca incluir linhas de atribuição de IA/colaboração (`Co-Authored-By:
  Claude...`, `Claude-Session: ...` ou similar) em commits, branches ou
  PRs — só a mensagem do próprio usuário, sem rodapé de assinatura.

## Antes de reportar "pronto"

- Mudança em `wifi_manager.sh`/`sync_backup.sh`/`update_models.sh`: não
  há como testar de fato fora do Raspberry Pi (dependem de `wlan0`,
  `hostapd`, `nmcli`, `iptables` reais). Validar sintaticamente
  (`bash -n arquivo.sh`) e revisar a lógica manualmente; deixar claro
  para o usuário que o teste real só acontece no hardware.
- Mudança em `gallery.py`: pode ser testada localmente com
  `python3 gallery.py <pasta-de-teste>` e acessando `localhost:8080`.
