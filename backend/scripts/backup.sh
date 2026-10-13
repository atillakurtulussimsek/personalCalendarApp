#!/bin/sh
# Nightly MySQL dump with retention. Runs inside the `backup` compose service
# (image mysql:8.4, which ships mysqldump). Env: DB_HOST DB_NAME DB_USER DB_PASSWORD
# BACKUP_DIR (default /backups) BACKUP_KEEP_DAYS (default 14) BACKUP_INTERVAL (default 86400 s).
set -eu
DIR="${BACKUP_DIR:-/backups}"
KEEP="${BACKUP_KEEP_DAYS:-14}"
INTERVAL="${BACKUP_INTERVAL:-86400}"
mkdir -p "$DIR"
while true; do
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  out="$DIR/${DB_NAME}-${stamp}.sql.gz"
  if mysqldump --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" \
      --single-transaction --quick --routines --triggers --set-gtid-purged=OFF "$DB_NAME" | gzip > "$out.tmp"; then
    mv "$out.tmp" "$out"
    echo "backup ok: $out ($(du -h "$out" | cut -f1))"
    find "$DIR" -name "${DB_NAME}-*.sql.gz" -mtime +"$KEEP" -delete
  else
    rm -f "$out.tmp"
    echo "backup FAILED at $stamp" >&2
  fi
  sleep "$INTERVAL"
done
