#!/bin/sh
# Runs inside the restic/restic container. Sets up crond then hands off to it.

CRON="${BACKUP_CRON:-0 2 * * *}"

printf 'Restic backup daemon\nRepository : %s\nSchedule   : %s\n' \
    "${RESTIC_REPOSITORY}" "${CRON}"

mkdir -p /etc/crontabs /var/log
printf '%s /bin/sh /scripts/backup.sh >> /var/log/restic.log 2>&1\n' "${CRON}" \
    > /etc/crontabs/root

printf 'Starting crond...\n'
exec crond -f -l 6
