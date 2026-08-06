#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file=${1:-$repo_root/docker-compose.yml}
failures=0

while IFS= read -r image; do
  if [[ ! "$image" =~ ^.+:[^/@]+@sha256:[0-9a-f]{64}$ ]]; then
    printf 'image is not tag-and-digest pinned: %s\n' "$image" >&2
    failures=$((failures + 1))
    continue
  fi

  tag=${image%@sha256:*}
  tag=${tag##*:}
  if [[ "$tag" == latest ]]; then
    printf 'image uses prohibited latest tag: %s\n' "$image" >&2
    failures=$((failures + 1))
  fi

  if [[ "$image" == ghcr.io/camptwright/* ]] &&
    [[ ! "$tag" =~ ^sha-[0-9a-f]{40}$ ]]; then
    printf 'in-house image does not use a full source-SHA tag: %s\n' "$image" >&2
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

wellthread_apps_count=$(
  awk '
    /^  wellthread-web:/ { in_service = 1; next }
    in_service && /^  [[:alnum:]_-]+:/ { in_service = 0 }
    in_service && /^[[:space:]]+profiles:[[:space:]]*\[apps\][[:space:]]*$/ { count++ }
    END { print count + 0 }
  ' "$compose_file"
)

if [[ $wellthread_apps_count -ne 1 ]]; then
  printf 'wellthread-web must belong to profile apps\n' >&2
  failures=$((failures + 1))
fi

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Compose image pins verified\n'
