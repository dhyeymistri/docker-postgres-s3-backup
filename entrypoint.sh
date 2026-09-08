#!/bin/sh
set -eu

# crond spawns backup.sh as a child of PID 1 but does NOT reliably forward
# the container's env on every Alpine/busybox build, so we snapshot the
# vars backup.sh needs into a file it sources explicitly. This is what
# actually caused the "cron ran, backup silently missing" failure mode.
env | grep -E '^(PG|S3_|AWS_|RETENTION_DAYS)=' > /etc/backup.env
chmod 600 /etc/backup.env

echo "${BACKUP_CRON:-0 2 * * *} /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

touch /var/log/backup.log

echo "[entrypoint] Backup cron installed: ${BACKUP_CRON:-0 2 * * *}"
echo "[entrypoint] Starting crond in foreground..."

crond -f -l 2 &
CROND_PID=$!

tail -F /var/log/backup.log &

wait "$CROND_PID"
