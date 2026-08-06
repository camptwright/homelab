#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$repo_root/tests/test-image-pins.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fixture="$test_root/docker-compose.yml"
output="$test_root/output"
digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
failures=0

write_fixture() {
  local web_profile=$1
  local web_image=$2
  local helper_image=$3

  cat >"$fixture" <<EOF
services:
  wellthread-web:
    profiles: [$web_profile]
    image: $web_image
  helper:
    profiles: [apps]
    image: $helper_image
EOF
}

expect_accept() {
  local label=$1
  if ! "$validator" "$fixture" >"$output" 2>&1; then
    printf '%s: valid fixture was rejected\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

expect_reject() {
  local label=$1
  if "$validator" "$fixture" >"$output" 2>&1; then
    printf '%s: invalid fixture unexpectedly passed\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

write_fixture apps \
  "ghcr.io/camptwright/wellthread-web:sha-1111111111111111111111111111111111111111@sha256:$digest" \
  "nginx:1.27-alpine@sha256:$digest"
expect_accept 'tag plus digest'

write_fixture apps \
  "ghcr.io/camptwright/wellthread-web:sha-1111111111111111111111111111111111111111@sha256:$digest" \
  'nginx:1.27-alpine'
expect_reject 'tag without digest'

write_fixture apps \
  "ghcr.io/camptwright/wellthread-web:sha-1111111111111111111111111111111111111111@sha256:$digest" \
  "nginx@sha256:$digest"
expect_reject 'untagged digest'

write_fixture apps \
  "ghcr.io/camptwright/wellthread-web:sha-1111111111111111111111111111111111111111@sha256:$digest" \
  "nginx:latest@sha256:$digest"
expect_reject 'latest plus digest'

write_fixture apps \
  "ghcr.io/camptwright/wellthread-web:v1@sha256:$digest" \
  "nginx:1.27-alpine@sha256:$digest"
expect_reject 'in-house image without source-SHA tag'

write_fixture pending \
  "ghcr.io/camptwright/wellthread-web:sha-1111111111111111111111111111111111111111@sha256:$digest" \
  "nginx:1.27-alpine@sha256:$digest"
expect_reject 'Wellthread outside apps profile'

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Image pin policy regressions verified\n'
