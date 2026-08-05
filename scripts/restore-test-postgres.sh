#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

backup_dir=${BACKUP_DIR:-/opt/backups/postgres}
container=${RESTORE_CONTAINER:-homelab-postgres-restore-test-$$}
dump=${1:-}

if [[ -z "$dump" ]]; then
  dump=$(find "$backup_dir" -maxdepth 1 -type f -name 'pg-*.sql.gz' -print | sort | tail -n 1)
fi

if [[ -z "$dump" || ! -f "$dump" ]]; then
  printf 'no completed Postgres dump found\n' >&2
  exit 66
fi

checksum="$dump.sha256"
if [[ ! -f "$checksum" ]]; then
  printf 'missing checksum: %s\n' "$checksum" >&2
  exit 66
fi

(
  cd "$(dirname "$dump")"
  sha256sum -c "$(basename "$checksum")" >/dev/null
)
gzip -t "$dump"

container_started=false
cleanup() {
  if [[ "$container_started" == true ]]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

docker run -d \
  --name "$container" \
  --tmpfs /var/lib/postgresql/data \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  pgvector/pgvector:pg16 >/dev/null
container_started=true

ready=false
for _ in $(seq 1 30); do
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  printf 'disposable Postgres did not become ready\n' >&2
  exit 70
fi

gzip -cd "$dump" | \
  docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U postgres >/dev/null

databases=$(docker exec "$container" psql -At -U postgres -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")

for expected in adjutant dashboard markets miniflux wellthread; do
  if ! grep -Fxq "$expected" <<<"$databases"; then
    printf 'restored cluster is missing database: %s\n' "$expected" >&2
    exit 65
  fi
done

printf 'restore verified: %s\n' "$dump"
