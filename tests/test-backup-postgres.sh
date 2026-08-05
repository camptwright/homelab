#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/compose"
cat >"$test_root/bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$*" == "compose exec -T postgres pg_dumpall -U postgres" ]]
printf '%s\n' '-- fake cluster dump' 'SELECT 1;'
FAKE_DOCKER
chmod 0755 "$test_root/bin/docker"
cat >"$test_root/bin/flock" <<'FAKE_FLOCK'
#!/usr/bin/env bash
exit 0
FAKE_FLOCK
chmod 0755 "$test_root/bin/flock"

PATH="$test_root/bin:$PATH" \
  BACKUP_DIR="$test_root/backups" \
  COMPOSE_DIR="$test_root/compose" \
  LOCK_FILE="$test_root/backup.lock" \
  "$repo_root/scripts/backup-postgres.sh"

dumps=("$test_root/backups"/pg-*.sql.gz)
[[ ${#dumps[@]} -eq 1 && -f ${dumps[0]} ]]

dump=${dumps[0]}
gzip -t "$dump"
(cd "$test_root/backups" && sha256sum -c "$(basename "$dump").sha256")
[[ $(stat -f '%Lp' "$test_root/backups" 2>/dev/null || stat -c '%a' "$test_root/backups") == 700 ]]
[[ $(stat -f '%Lp' "$dump" 2>/dev/null || stat -c '%a' "$dump") == 600 ]]
[[ ! -e "$test_root/backups/.pg-"*'.tmp' ]]

printf 'backup behavior verified\n'
