#!/bin/bash
# Sincroniza a pasta de imagens com o Pi backup via rsync/SSH.
# Chamado pelo wifi_manager.sh quando conectado à internet.

BACKUP_CONF="/etc/wifi_manager/backup.conf"
ENV_FILE="/etc/wifi_manager/.env"
FILTER_FILE="/etc/wifi_manager/rsync_filter.conf"
SSH_KEY="/root/.ssh/wifi_manager_backup"
LOG="/var/log/wifi_manager.log"
LOCK="/var/run/sync_backup.lock"
STATUS_DIR="/var/lib/wifi_manager"
STATUS_FILE="$STATUS_DIR/last_sync"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $1" | tee -a "$LOG"; }

mkdir -p "$STATUS_DIR" 2>/dev/null || true

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
BACKUP_PORT="${BACKUP_PORT:-22}"
SYNC_MAX_RETRIES="${SYNC_MAX_RETRIES:-3}"
SYNC_RETRY_DELAY="${SYNC_RETRY_DELAY:-90}"

FILTER_ARGS=()
if [ -f "$FILTER_FILE" ]; then
    FILTER_ARGS=(--prune-empty-dirs --filter="merge $FILTER_FILE")
else
    log "rsync_filter.conf não encontrado ($FILTER_FILE) — sincronizando $IMAGE_DIR sem filtro."
fi

log "Iniciando sync: $IMAGE_DIR → $DEST (porta $BACKUP_PORT)"

success=false
for attempt in $(seq 1 "$SYNC_MAX_RETRIES"); do
    rsync -az \
        --partial \
        --timeout=30 \
        "${FILTER_ARGS[@]}" \
        -e "ssh -p $BACKUP_PORT -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
        "$IMAGE_DIR/" \
        "$DEST" 2>&1 | tee -a "$LOG"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        success=true
        break
    fi

    if [ "$attempt" -lt "$SYNC_MAX_RETRIES" ]; then
        log "Tentativa $attempt/$SYNC_MAX_RETRIES falhou — nova tentativa em ${SYNC_RETRY_DELAY}s"
        sleep "$SYNC_RETRY_DELAY"
    fi
done

if [ "$success" = true ]; then
    log "Sync concluído com sucesso."
    echo "SUCCESS $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
else
    log "Sync falhou após $SYNC_MAX_RETRIES tentativas — será tentado novamente no próximo intervalo."
    echo "FAILED $(date '+%Y-%m-%d %H:%M:%S') (${SYNC_MAX_RETRIES} tentativas)" > "$STATUS_FILE"
    exit 1
fi
