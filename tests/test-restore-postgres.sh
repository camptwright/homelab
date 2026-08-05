#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/backups"
dump="$test_root/backups/pg-20260805T120000Z.sql.gz"
printf '%s\n' '-- fake cluster dump' 'SELECT 1;' | gzip -9 >"$dump"
(cd "$(dirname "$dump")" && sha256sum "$(basename "$dump")" >"$(basename "$dump").sha256")

cat >"$test_root/bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${DOCKER_STATE:?}"

case "${1:-}" in
  run)
    [[ "$*" == *'--tmpfs /var/lib/postgresql/data'* ]]
    [[ "$*" == *'pgvector/pgvector:pg16'* ]]
    touch "$DOCKER_STATE"
    printf 'fake-container-id\n'
    ;;
  exec)
    if [[ "$*" == *'pg_isready -U postgres'* ]]; then
      [[ -e "$DOCKER_STATE" ]]
    elif [[ "$*" == *'psql -v ON_ERROR_STOP=1 -U postgres'* ]]; then
      [[ " $* " == *' -i '* ]]
      grep -q 'SELECT 1;' /dev/stdin
    elif [[ "$*" == *'psql -At -U postgres'* ]]; then
      printf '%s\n' adjutant dashboard markets miniflux wellthread
    else
      exit 64
    fi
    ;;
  rm)
    [[ " $* " == *' -f '* ]]
    rm -f "$DOCKER_STATE"
    ;;
  *)
    exit 64
    ;;
esac
FAKE_DOCKER
chmod 0755 "$test_root/bin/docker"

output=$(
  PATH="$test_root/bin:$PATH" \
    BACKUP_DIR="$test_root/backups" \
    DOCKER_STATE="$test_root/container-running" \
    RESTORE_CONTAINER="restore-test-fixture" \
    "$repo_root/scripts/restore-test-postgres.sh" "$dump"
)

[[ "$output" == *"restore verified: $dump"* ]]
[[ ! -e "$test_root/container-running" ]]

printf 'restore behavior verified\n'
