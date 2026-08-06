#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/docker-compose.yml"
failures=0

while IFS= read -r image; do
  if [[ ! "$image" =~ @sha256:[[:xdigit:]]{64}$ ]]; then
    printf 'image is not digest-pinned: %s\n' "$image" >&2
    failures=$((failures + 1))
  fi
done < <(
  awk '
    /^[[:space:]]+image:/ {
      sub(/^[[:space:]]*image:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*/, "")
      print
    }
  ' "$compose_file"
)

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Compose image pins verified\n'
