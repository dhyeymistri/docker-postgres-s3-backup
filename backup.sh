#!/bin/sh
set -eu

# Load the env snapshot written by entrypoint.sh — cron doesn't reliably
# inherit container env on every busybox build, so we don't depend on it.
[ -f /etc/backup.env ] && . /etc/backup.env

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="backup_${PGDATABASE}_${TIMESTAMP}.sql.gz"
TEMP_SQL="/tmp/${FILENAME%.gz}"
TEMP_GZ="/tmp/${FILENAME}"

echo "[$(date)] Starting backup of ${PGDATABASE}..."
export PGPASSWORD="${PGPASSWORD}"

# Dump to a file first and check pg_dump's own exit code directly, rather
# than piping into gzip and relying on `set -o pipefail` — busybox ash's
# pipefail support is version-dependent, and without it a failed pg_dump
# still exits 0 through the pipe, silently uploading an empty/garbage backup.
if ! pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -f "${TEMP_SQL}"; then
    echo "[$(date)] ERROR: pg_dump failed, aborting backup." >&2
    rm -f "${TEMP_SQL}"
    exit 1
fi

if [ ! -s "${TEMP_SQL}" ]; then
    echo "[$(date)] ERROR: pg_dump produced an empty file, aborting backup." >&2
    rm -f "${TEMP_SQL}"
    exit 1
fi

gzip "${TEMP_SQL}"

echo "[$(date)] Uploading ${FILENAME} to s3://${S3_BUCKET}/..."
if ! aws --endpoint-url="${S3_ENDPOINT}" s3 cp "${TEMP_GZ}" "s3://${S3_BUCKET}/${FILENAME}"; then
    echo "[$(date)] ERROR: upload failed, leaving local copy at ${TEMP_GZ}" >&2
    exit 1
fi
rm -f "${TEMP_GZ}"

echo "[$(date)] Cleaning up archives older than ${RETENTION_DAYS} days..."

# Portable (busybox) epoch math instead of GNU `date -d "-N days"`.
CUTOFF_EPOCH=$(( $(date +%s) - RETENTION_DAYS * 86400 ))

aws --endpoint-url="${S3_ENDPOINT}" s3 ls "s3://${S3_BUCKET}/" | while read -r fDate fTime fSize fName; do
    [ -z "${fName:-}" ] && continue

    # busybox date needs an explicit input format via -D; GNU date parses
    # "YYYY-MM-DD HH:MM:SS" without help, so try -D first and fall back.
    fileEpoch=$(date -D "%Y-%m-%d %H:%M:%S" -d "${fDate} ${fTime}" +%s 2>/dev/null \
        || date -d "${fDate} ${fTime}" +%s 2>/dev/null \
        || echo "")

    if [ -z "$fileEpoch" ]; then
        echo "[$(date)] WARNING: could not parse date for ${fName}, skipping." >&2
        continue
    fi

    if [ "$fileEpoch" -lt "$CUTOFF_EPOCH" ]; then
        echo "Deleting expired backup: ${fName}"
        aws --endpoint-url="${S3_ENDPOINT}" s3 rm "s3://${S3_BUCKET}/${fName}"
    fi
done

echo "[$(date)] Backup process completed successfully."
