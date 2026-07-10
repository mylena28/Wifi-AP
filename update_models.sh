#!/bin/bash
# Atualiza projetos de modelos via git pull + docker compose.
# Chamado pelo wifi_manager.sh quando conectado à internet.

PROJECTS=(
    "/mnt/nvme/Monitoramento/DrowsyDriving"
    "/mnt/nvme/Monitoramento/FATIGUE"
)

WIFI_AP_REPO="/mnt/nvme/Wifi-AP"

LOG="/var/log/wifi_manager.log"
LOCK="/var/run/update_models.lock"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [update] $1" | tee -a "$LOG"; }

# Impede execuções simultâneas
if [ -f "$LOCK" ] && kill -0 "$(cat $LOCK)" 2>/dev/null; then
    log "Update já em andamento (PID $(cat $LOCK)) — ignorando chamada."
    exit 0
fi
echo $$ > "$LOCK"
trap "rm -f $LOCK" EXIT

update_project() {
    local repo="$1"
    local name
    name=$(basename "$repo")

    if [ ! -d "$repo/.git" ]; then
        log "$name: diretório git não encontrado — pulando."
        return 1
    fi

    cd "$repo" || return 1

    git fetch origin 2>/dev/null
    local local_ref remote_ref
    local_ref=$(git rev-parse HEAD 2>/dev/null)
    remote_ref=$(git rev-parse origin/main 2>/dev/null)

    if [ "$local_ref" = "$remote_ref" ]; then
        log "$name: já está na versão mais recente."
        return 0
    fi

    log "$name: nova versão detectada. Atualizando..."
    git pull origin main 2>&1 | tee -a "$LOG"

    if [ ! -f "$repo/docker-compose.yml" ] && [ ! -f "$repo/docker-compose.yaml" ]; then
        log "$name: sem docker-compose.yml — apenas git pull realizado."
        return 0
    fi

    log "$name: rebuild e reinício do container..."
    docker compose build 2>&1 | tee -a "$LOG"
    docker compose up -d 2>&1 | tee -a "$LOG"
    log "$name: update concluído."
}

update_wifi_ap() {
    [ -d "$WIFI_AP_REPO/.git" ] || { log "Wifi-AP: repo não encontrado em $WIFI_AP_REPO — pulando."; return 1; }

    cd "$WIFI_AP_REPO" || return 1

    git fetch origin 2>/dev/null
    local local_ref remote_ref
    local_ref=$(git rev-parse HEAD 2>/dev/null)
    remote_ref=$(git rev-parse origin/main 2>/dev/null)

    if [ "$local_ref" = "$remote_ref" ]; then
        log "Wifi-AP: já está na versão mais recente."
        return 0
    fi

    log "Wifi-AP: nova versão detectada. Atualizando..."
    git pull origin main 2>&1 | tee -a "$LOG"

    cp "$WIFI_AP_REPO/wifi_manager.sh"  /usr/local/bin/wifi_manager.sh
    cp "$WIFI_AP_REPO/sync_backup.sh"   /usr/local/bin/sync_backup.sh
    cp "$WIFI_AP_REPO/update_models.sh" /usr/local/bin/update_models.sh
    chmod +x /usr/local/bin/wifi_manager.sh \
             /usr/local/bin/sync_backup.sh \
             /usr/local/bin/update_models.sh

    log "Wifi-AP: rebuild e reinício do container da galeria..."
    docker compose build 2>&1 | tee -a "$LOG"
    docker compose up -d 2>&1 | tee -a "$LOG"

    # --no-block: enfileira o restart no systemd e retorna na hora, sem
    # esperar o job terminar (este script é filho do próprio serviço que
    # está sendo reiniciado, então esperar o mataria no meio do restart).
    log "Wifi-AP: agendando restart do wifi-manager.service..."
    systemctl restart --no-block wifi-manager.service
    log "Wifi-AP: update concluído."
}

log "Iniciando verificação de atualizações dos modelos..."
for project in "${PROJECTS[@]}"; do
    update_project "$project"
done
update_wifi_ap
log "Verificação concluída."
