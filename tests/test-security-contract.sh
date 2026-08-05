#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/docker-compose.yml"
security_file="$repo_root/SECURITY.md"

service_block() {
  local service=$1
  awk -v heading="  ${service}:" '
    $0 == heading { in_service = 1 }
    in_service && $0 != heading && /^  [[:alnum:]_-]+:/ { exit }
    in_service { print }
  ' "$compose_file"
}

assert_block_contains() {
  local service=$1
  local text=$2
  local block
  block=$(service_block "$service")
  grep -Fq -- "$text" <<<"$block" || {
    printf '%s is missing security control: %s\n' "$service" "$text" >&2
    exit 1
  }
}

[[ -s "$security_file" ]] || {
  printf 'SECURITY.md is missing or empty\n' >&2
  exit 1
}

assert_block_contains litellm 'user: "65532:65532"'
assert_block_contains litellm 'read_only: true'
assert_block_contains litellm 'cap_drop: [ALL]'
assert_block_contains litellm 'security_opt: ["no-new-privileges:true"]'
assert_block_contains litellm 'tmpfs: ["/tmp:rw,noexec,nosuid,size=64m"]'
assert_block_contains litellm 'pids_limit: 256'
assert_block_contains litellm 'ports: ["0.0.0.0:4000:4000"]'
assert_block_contains litellm 'healthcheck:'

assert_block_contains beszel-agent 'read_only: true'
assert_block_contains beszel-agent 'cap_drop: [ALL]'
assert_block_contains beszel-agent 'security_opt: ["no-new-privileges:true"]'
assert_block_contains beszel-agent 'tmpfs: ["/tmp:rw,noexec,nosuid,size=16m"]'
assert_block_contains beszel-agent 'pids_limit: 128'
assert_block_contains beszel-agent '"/var/run/docker.sock:/var/run/docker.sock:ro"'

grep -Fq 'root-equivalent' "$security_file"
grep -Fq 'control of the Docker daemon' "$security_file"
grep -Fq 'does not make the Docker API' "$security_file"
grep -Fq 'trusted private LAN' "$security_file"

for secret_path in .env .env.adjutant .env.bak.test .env.production.bak.test; do
  git -C "$repo_root" check-ignore -q "$secret_path" || {
    printf 'secret path is not ignored: %s\n' "$secret_path" >&2
    exit 1
  }
done

printf 'Security contract verified\n'
