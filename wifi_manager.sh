#!/bin/bash
# Gerenciador Wi-Fi: AP no boot → scan de redes → cliente → scan ao perder conexão

NETWORKS_FILE="/etc/wifi_manager/networks.conf"
BACKUP_CONF="/etc/wifi_manager/backup.conf"
AP_TIMEOUT=900        # 15 min sem nenhum cliente → vai para scan
CHECK_AP_INTERVAL=30  # intervalo de verificação de clientes no AP (segundos)
CHECK_WIFI_INTERVAL=60 # intervalo de verificação da conexão WiFi (segundos)
LOG="/var/log/wifi_manager.log"
HOSTAPD_PID=""
BACKUP_INTERVAL=3600  # padrão; sobrescrito pelo backup.conf

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

state="AP"
transition_to() { state="$1"; log "→ $state"; }

# ── Limpeza ao encerrar ───────────────────────────────────────────────────────

cleanup() {
    log "wifi_manager encerrando..."
    _stop_hostapd
    systemctl stop dnsmasq 2>/dev/null || true
    _ap_iptables_del
    ip addr flush dev wlan0 2>/dev/null || true
    _nm_manage_wlan0
}
trap cleanup EXIT SIGTERM SIGINT

# ── Helpers de iptables ───────────────────────────────────────────────────────

_ap_iptables_add() {
    iptables -t nat -C PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || \
        iptables -t nat -I PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port 8080
    iptables -C INPUT   -i wlan0 -j ACCEPT 2>/dev/null || iptables -I INPUT   -i wlan0 -j ACCEPT
    iptables -C FORWARD -i wlan0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i wlan0 -j ACCEPT
}

_ap_iptables_del() {
    iptables -t nat -D PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || true
    iptables -D INPUT   -i wlan0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i wlan0 -j ACCEPT 2>/dev/null || true
}

# ── Helpers de hostapd ────────────────────────────────────────────────────────

_start_hostapd() {
    /usr/sbin/hostapd /etc/hostapd/hostapd.conf &
    HOSTAPD_PID=$!
    log "hostapd iniciado (PID $HOSTAPD_PID)"
}

_stop_hostapd() {
    if [ -n "$HOSTAPD_PID" ] && kill -0 "$HOSTAPD_PID" 2>/dev/null; then
        kill "$HOSTAPD_PID"
        wait "$HOSTAPD_PID" 2>/dev/null || true
    fi
    pkill -f "hostapd /etc/hostapd" 2>/dev/null || true
    HOSTAPD_PID=""
}

# ── Estado AP ────────────────────────────────────────────────────────────────

_nm_unmanage_wlan0() {
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-ap-mode.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    nmcli general reload conf
    sleep 3
}

_nm_manage_wlan0() {
    rm -f /etc/NetworkManager/conf.d/99-ap-mode.conf
    nmcli general reload conf
    sleep 3
    rfkill unblock wifi 2>/dev/null || true
    nmcli radio wifi on 2>/dev/null || true
    nmcli device set wlan0 managed yes 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    sleep 1
    ip link set wlan0 up 2>/dev/null || true
}

_start_ap() {
    log "Iniciando modo AP..."
    nmcli device disconnect wlan0 2>/dev/null || true
    _nm_unmanage_wlan0
    rfkill unblock wifi 2>/dev/null || true
    iw reg set BR 2>/dev/null || true

    ip link set wlan0 down 2>/dev/null || true
    sleep 1
    ip addr flush dev wlan0 2>/dev/null || true
    ip addr add 192.168.50.1/24 dev wlan0
    ip link set wlan0 up

    _ap_iptables_add
    _start_hostapd
    sleep 3
    systemctl restart dnsmasq
    log "AP ativo — PiGaleria @ 192.168.50.1:8080"
}

_stop_ap() {
    log "Parando modo AP..."
    _stop_hostapd
    systemctl stop dnsmasq 2>/dev/null || true
    _ap_iptables_del
    ip link set wlan0 down 2>/dev/null || true
    ip addr flush dev wlan0 2>/dev/null || true
    _nm_manage_wlan0
    sleep 2
}

_ap_client_count() {
    iw dev wlan0 station dump 2>/dev/null | grep -c "^Station"
}

run_ap_state() {
    _start_ap

    local start had_client prev_clients clients now
    start=$(date +%s)
    had_client=false
    prev_clients=0

    log "AP ativo. Aguardando clientes (timeout: $((AP_TIMEOUT/60)) min)..."

    while true; do
        sleep $CHECK_AP_INTERVAL

        clients=$(_ap_client_count)
        now=$(date +%s)

        if [ "$clients" -gt 0 ]; then
            [ "$had_client" = false ] && log "Primeiro cliente conectado ao AP."
            had_client=true
        fi

        # Último cliente acabou de sair → scan imediato
        if [ "$had_client" = true ] && [ "$clients" -eq 0 ] && [ "$prev_clients" -gt 0 ]; then
            log "Último cliente desconectou. Indo para scan WiFi..."
            transition_to "WIFI_SCAN"
            return
        fi

        # Timeout sem nenhum cliente desde o início
        if [ "$had_client" = false ] && [ $(( now - start )) -ge $AP_TIMEOUT ]; then
            log "Timeout: $((AP_TIMEOUT/60)) min sem clientes. Indo para scan WiFi..."
            transition_to "WIFI_SCAN"
            return
        fi

        prev_clients=$clients
    done
}

# ── Estado WIFI_SCAN ─────────────────────────────────────────────────────────

_enable_nm() {
    nmcli device set wlan0 managed yes 2>/dev/null || true
    ip link set wlan0 up 2>/dev/null || true
    sleep 5
}

_get_visible_ssids() {
    nmcli device wifi rescan ifname wlan0 2>/dev/null || true
    sleep 3
    nmcli -t -f SSID device wifi list ifname wlan0 2>/dev/null \
        | grep -v '^$' | grep -v '^--$' | sort -u
}

_is_connected() {
    nmcli -t -f GENERAL.STATE device show wlan0 2>/dev/null | grep -q "100 (connected)"
}

_try_nm_saved() {
    local visible="$1"
    local connections ssid conn

    # Lista conexões WiFi salvas no NM
    connections=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | grep -E ':(wifi|802-11-wireless)$' | cut -d: -f1)

    [ -z "$connections" ] && return 1

    while IFS= read -r conn; do
        [ -z "$conn" ] && continue
        ssid=$(nmcli -g 802-11-wireless.ssid connection show "$conn" 2>/dev/null)
        [ -z "$ssid" ] && continue

        if echo "$visible" | grep -qxF "$ssid"; then
            log "Tentando conexão NM salva: '$ssid'"
            if nmcli connection up "$conn" ifname wlan0 2>/dev/null; then
                sleep 5
                if _is_connected; then
                    log "Conectado via perfil NM: $ssid"
                    return 0
                fi
            fi
        fi
    done <<< "$connections"

    return 1
}

_try_networks_file() {
    local visible="$1"

    [ -f "$NETWORKS_FILE" ] || { log "networks.conf não encontrado: $NETWORKS_FILE"; return 1; }

    local ssid pass result

    while IFS='=' read -r ssid pass; do
        [[ "$ssid" =~ ^[[:space:]]*# ]] && continue
        ssid="${ssid#"${ssid%%[![:space:]]*}"}"
        ssid="${ssid%"${ssid##*[![:space:]]}"}"
        [ -z "$ssid" ] && continue

        if echo "$visible" | grep -qxF "$ssid"; then
            log "Tentando rede do arquivo: '$ssid'"
            if [ -z "$pass" ]; then
                nmcli device wifi connect "$ssid" ifname wlan0 2>/dev/null
                result=$?
            else
                nmcli device wifi connect "$ssid" password "$pass" ifname wlan0 2>/dev/null
                result=$?
            fi

            if [ $result -eq 0 ]; then
                sleep 5
                if _is_connected; then
                    log "Conectado e salvo no NM: $ssid"
                    return 0
                fi
            fi
        fi
    done < "$NETWORKS_FILE"

    return 1
}

run_wifi_scan_state() {
    _stop_ap
    _enable_nm

    log "Escaneando redes disponíveis..."
    local visible
    visible=$(_get_visible_ssids)

    if [ -z "$visible" ]; then
        log "Nenhuma rede visível. Voltando ao AP..."
        transition_to "AP"
        return
    fi

    log "Redes visíveis: $(echo "$visible" | tr '\n' ',' | sed 's/,$//')"

    if _try_nm_saved "$visible" || _try_networks_file "$visible"; then
        transition_to "WIFI_CLIENT"
        return
    fi

    log "Nenhuma rede disponível. Voltando ao AP..."
    transition_to "AP"
}

# ── Backup ───────────────────────────────────────────────────────────────────

_load_backup_interval() {
    [ -f "$BACKUP_CONF" ] && source "$BACKUP_CONF" 2>/dev/null || true
}

_run_backup() {
    if [ ! -f "$BACKUP_CONF" ]; then return; fi
    source "$BACKUP_CONF" 2>/dev/null || return
    [ -z "$BACKUP_HOST" ] && return  # não configurado ainda
    log "Disparando sync de backup em background..."
    /usr/local/bin/sync_backup.sh &
}

# ── Estado WIFI_CLIENT ────────────────────────────────────────────────────────

run_wifi_client_state() {
    _load_backup_interval

    log "Modo WiFi cliente ativo. Checando conexão a cada ${CHECK_WIFI_INTERVAL}s..."

    _run_backup  # sync imediato ao conectar

    local last_backup
    last_backup=$(date +%s)

    while true; do
        sleep $CHECK_WIFI_INTERVAL

        if ! _is_connected; then
            log "Conexão WiFi perdida. Indo para scan..."
            transition_to "WIFI_SCAN"
            return
        fi

        local now
        now=$(date +%s)
        if [ $(( now - last_backup )) -ge "$BACKUP_INTERVAL" ]; then
            _run_backup
            last_backup=$now
        fi
    done
}

# ── Loop principal ────────────────────────────────────────────────────────────

main() {
    log "======================================="
    log " wifi_manager iniciado"
    log "======================================="

    while true; do
        case "$state" in
        AP)          run_ap_state ;;
        WIFI_SCAN)   run_wifi_scan_state ;;
        WIFI_CLIENT) run_wifi_client_state ;;
        esac
    done
}

main
