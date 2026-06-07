#!/bin/sh
# Picks 2 random files from the latest snapshot and restores them to /tmp.
# Run with: docker exec restic-backup /bin/sh /scripts/restore-test.sh

RESTORE_DIR="/tmp/restic-test-$$"
mkdir -p "$RESTORE_DIR"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "=== Restore test started ==="

log "Connecting to repository: ${RESTIC_REPOSITORY}"
if ! restic snapshots > /dev/null; then
    log "ERROR: cannot read repository (see error above)"
    exit 1
fi

SNAP=$(restic snapshots --latest 1 --json \
    | grep -o '"short_id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SNAP" ]; then
    log "ERROR: repository is reachable but contains no snapshots"
    exit 1
fi

log "Latest snapshot: ${SNAP}"
log "Listing files..."

FILELIST=$(restic ls --json "$SNAP" 2>/dev/null \
    | grep '"type":"file"' \
    | grep -o '"path":"[^"]*"' \
    | cut -d'"' -f4)

TOTAL=$(printf '%s\n' "$FILELIST" | grep -c . || true)
log "Total files in snapshot: ${TOTAL}"

if [ "$TOTAL" -lt 1 ]; then
    log "ERROR: snapshot contains no files"
    exit 1
fi

# Pick 2 random files using $RANDOM (busybox ash supports it)
FILE1=$(printf '%s\n' "$FILELIST" | sed -n "$((RANDOM % TOTAL + 1))p")
REMAINING=$(printf '%s\n' "$FILELIST" | grep -vxF "$FILE1")
REM_TOTAL=$(printf '%s\n' "$REMAINING" | grep -c . || true)

if [ "$REM_TOTAL" -gt 0 ]; then
    FILE2=$(printf '%s\n' "$REMAINING" | sed -n "$((RANDOM % REM_TOTAL + 1))p")
else
    FILE2=""
fi

log "Selected: ${FILE1}"
[ -n "$FILE2" ] && log "Selected: ${FILE2}"

PASS=0
FAIL=0

restore_and_check() {
    local file="$1"
    log "Restoring ${file}..."
    if restic restore "$SNAP" --target "$RESTORE_DIR" --include "$file" 2>/dev/null; then
        local dest="${RESTORE_DIR}${file}"
        if [ -f "$dest" ]; then
            SIZE=$(wc -c < "$dest")
            ORIG_SUM=$(sha256sum "$file" | cut -d' ' -f1)
            REST_SUM=$(sha256sum "$dest" | cut -d' ' -f1)
            if [ "$ORIG_SUM" = "$REST_SUM" ]; then
                log "  OK — ${SIZE} bytes, sha256 matches (${ORIG_SUM})"
                PASS=$((PASS + 1))
            else
                log "  FAIL — checksum mismatch"
                log "    original : ${ORIG_SUM}"
                log "    restored : ${REST_SUM}"
                FAIL=$((FAIL + 1))
            fi
        else
            log "  FAIL — file missing after restore at ${dest}"
            FAIL=$((FAIL + 1))
        fi
    else
        log "  FAIL — restic restore returned error"
        FAIL=$((FAIL + 1))
    fi
}

restore_and_check "$FILE1"
[ -n "$FILE2" ] && restore_and_check "$FILE2"

TOTAL_TESTED=$((PASS + FAIL))
log "=== Result: ${PASS}/${TOTAL_TESTED} passed ==="

log "Restored files available at: ${RESTORE_DIR}"
[ "$FAIL" -eq 0 ]
