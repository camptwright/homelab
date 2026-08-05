#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/docker-compose.yml"
pending_exception='ghcr.io/camptwright/wellthread-web:latest'
exception_count=0
failures=0

while IFS= read -r image; do
  if [[ "$image" == "$pending_exception" ]]; then
    exception_count=$((exception_count + 1))
    continue
  fi

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

if [[ $exception_count -ne 1 ]]; then
  printf 'expected exactly one pending wellthread-web exception, found %d\n' "$exception_count" >&2
  failures=$((failures + 1))
fi

pending_profile_count=$(
  awk '
    /^  wellthread-web:/ { in_service = 1; next }
    in_service && /^  [[:alnum:]_-]+:/ { in_service = 0 }
    in_service && /^[[:space:]]+profiles:[[:space:]]*\[pending\][[:space:]]*$/ { count++ }
    END { print count + 0 }
  ' "$compose_file"
)

if [[ $pending_profile_count -ne 1 ]]; then
  printf 'wellthread-web must remain in profile pending while its image is unpinned\n' >&2
  failures=$((failures + 1))
fi

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Compose image pins verified\n'
