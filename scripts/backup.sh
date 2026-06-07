#!/bin/sh
# Backs up /data/config and /data/media to Backblaze B2 via restic.
# Keeps the last 3 snapshots. Sends result to Telegram.

START=$(date +%s)
STATUS="success"
ERROR=""

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

send_telegram() {
    wget -q -O /dev/null \
        --header 'Content-Type: application/json' \
        --post-data "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"$1\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>/dev/null || true
}

log "=== Backup started ==="

if ! restic snapshots > /dev/null 2>&1; then
    log "Initializing new repository..."
    restic init || { ERROR="repo init failed"; STATUS="failed"; }
fi

if [ "$STATUS" = "success" ]; then
    log "Backing up /data/config and /data/media..."
    if ! restic backup /data/config /data/media --tag self-hosted; then
        ERROR="restic backup failed"
        STATUS="failed"
    fi
fi

if [ "$STATUS" = "success" ]; then
    log "Pruning — keeping last 3 snapshots..."
    restic forget --keep-last 3 --prune || true
    SNAP=$(restic snapshots --latest 1 --json 2>/dev/null \
        | grep -o '"short_id":"[^"]*"' | cut -d'"' -f4)
fi

END=$(date +%s)
DURATION=$((END - START))

if [ "$STATUS" = "success" ]; then
    MSG="[OK] Backup complete | $(date '+%Y-%m-%d %H:%M') | ${DURATION}s | snap: ${SNAP} | paths: config, media"
    log "Done in ${DURATION}s — snapshot ${SNAP}"
else
    MSG="[FAIL] Backup failed | $(date '+%Y-%m-%d %H:%M') | ${ERROR}"
    log "FAILED: ${ERROR}"
fi

send_telegram "$MSG"
