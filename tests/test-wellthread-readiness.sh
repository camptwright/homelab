#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/docker-compose.yml"
failures=0

service_block() {
  local service=$1
  awk -v service="$service" '
    $0 == "  " service ":" { in_service = 1 }
    in_service && $0 ~ /^  [[:alnum:]_-]+:/ && $0 != "  " service ":" { exit }
    in_service { print }
  ' "$compose_file"
}

rest_block=$(service_block wellthread-rest)
gateway_block=$(service_block wellthread-gateway)

if ! grep -Fq 'PGRST_ADMIN_SERVER_PORT: "3001"' <<<"$rest_block"; then
  printf 'wellthread-rest must enable its admin readiness server on port 3001\n' >&2
  failures=$((failures + 1))
fi

if ! grep -Fq 'test: ["CMD", "postgrest", "--ready"]' <<<"$rest_block"; then
  printf 'wellthread-rest healthcheck must query the running admin /ready endpoint\n' >&2
  failures=$((failures + 1))
fi

if ! grep -Fq 'wellthread-rest: {condition: service_healthy}' <<<"$gateway_block"; then
  printf 'wellthread-gateway must wait for wellthread-rest readiness\n' >&2
  failures=$((failures + 1))
fi

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Wellthread readiness contract verified\n'
