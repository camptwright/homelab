#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

grep -oE '\$\{[A-Z0-9_]+' "$repo_root/docker-compose.yml" |
  sed 's/^${//' | sort -u >"$test_root/compose-vars"

sed -nE 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' "$repo_root/env.example" |
  sort -u >"$test_root/example-vars"

comm -23 "$test_root/compose-vars" "$test_root/example-vars" >"$test_root/missing"
if [[ -s "$test_root/missing" ]]; then
  printf 'env.example is missing Compose variables:\n' >&2
  sed 's/^/  - /' "$test_root/missing" >&2
  exit 1
fi

printf 'Compose environment contract verified\n'
