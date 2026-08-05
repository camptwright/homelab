#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

backup_dir=${BACKUP_DIR:-/opt/backups/postgres}
compose_dir=${COMPOSE_DIR:-/opt/homelab}
lock_file=${LOCK_FILE:-/run/lock/homelab-postgres-backup.lock}
retention_days=${RETENTION_DAYS:-14}

mkdir -p "$backup_dir"
chmod 0700 "$backup_dir"

exec 9>"$lock_file"
if ! flock -n 9; then
  printf 'backup already running\n' >&2
  exit 75
fi

find "$backup_dir" -maxdepth 1 -type f -name '.pg-*.tmp' -mtime +1 -delete

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
temporary="$backup_dir/.pg-$timestamp.sql.gz.tmp"
completed="$backup_dir/pg-$timestamp.sql.gz"
trap 'rm -f -- "$temporary"' EXIT

cd "$compose_dir"
docker compose exec -T postgres pg_dumpall -U postgres | gzip -9 >"$temporary"
test -s "$temporary"
gzip -t "$temporary"

mv "$temporary" "$completed"
chmod 0600 "$completed"
(
  cd "$backup_dir"
  sha256sum "$(basename "$completed")" >"$(basename "$completed").sha256"
)
chmod 0600 "$completed.sha256"

find "$backup_dir" -maxdepth 1 -type f \
  \( -name 'pg-*.sql.gz' -o -name 'pg-*.sql.gz.sha256' \) \
  -mtime "+$retention_days" -delete

bytes=$(wc -c <"$completed" | tr -d ' ')
printf 'backup complete: %s (%s bytes)\n' "$completed" "$bytes"
