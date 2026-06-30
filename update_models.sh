#!/bin/bash
# Atualiza projetos de modelos via git pull + docker compose.
# Chamado pelo wifi_manager.sh quando conectado à internet.

PROJECTS=(
    "/mnt/nvme/DrowsyDriving"
    "/mnt/nvme/FATIGUE"
)

LOG="/var/log/wifi_manager.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [update] $1" | tee -a "$LOG"; }

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

log "Iniciando verificação de atualizações dos modelos..."
for project in "${PROJECTS[@]}"; do
    update_project "$project"
done
log "Verificação concluída."
