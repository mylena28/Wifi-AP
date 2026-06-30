#!/bin/bash
# Sincroniza a pasta de imagens com o Pi backup via rsync/SSH.
# Chamado pelo wifi_manager.sh quando conectado à internet.

BACKUP_CONF="/etc/wifi_manager/backup.conf"
ENV_FILE="/etc/wifi_manager/.env"
SSH_KEY="/root/.ssh/wifi_manager_backup"
LOG="/var/log/wifi_manager.log"
LOCK="/var/run/sync_backup.lock"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $1" | tee -a "$LOG"; }

# Impede execuções simultâneas
if [ -f "$LOCK" ] && kill -0 "$(cat $LOCK)" 2>/dev/null; then
    log "Sync já em andamento (PID $(cat $LOCK)) — ignorando chamada."
    exit 0
fi
echo $$ > "$LOCK"
trap "rm -f $LOCK" EXIT

# Carrega configurações
[ -f "$BACKUP_CONF" ] || { log "backup.conf não encontrado: $BACKUP_CONF"; exit 1; }
source "$BACKUP_CONF"

[ -f "$ENV_FILE" ] || { log ".env não encontrado: $ENV_FILE"; exit 1; }
source "$ENV_FILE"

# Valida campos obrigatórios
if [ -z "$BACKUP_HOST" ]; then
    log "BACKUP_HOST não configurado em backup.conf — sync ignorado."
    exit 0
fi

if [ -z "$IMAGE_DIR" ]; then
    log "IMAGE_DIR não definido em .env — sync ignorado."
    exit 0
fi

if [ ! -d "$IMAGE_DIR" ]; then
    log "Pasta de imagens não encontrada: $IMAGE_DIR"
    exit 1
fi

DEST="${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_PATH}/"

log "Iniciando sync: $IMAGE_DIR → $DEST"

rsync -az \
    --no-delete \
    --partial \
    --timeout=30 \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    "$IMAGE_DIR/" \
    "$DEST" 2>&1 | tee -a "$LOG"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "Sync concluído com sucesso."
else
    log "Sync falhou — será tentado novamente no próximo intervalo."
    exit 1
fi
