#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

required_docs=(
  README.md
  NEXT-STEPS.md
  SETUP.md
  IMAGE-PINS.md
  CLAUDE.md
  PROMPTS-HOMELAB.md
  K8S-CLUSTER-GUIDE.md
)

for document in "${required_docs[@]}"; do
  [[ -s "$repo_root/$document" ]] || {
    printf 'required documentation is missing or empty: %s\n' "$document" >&2
    exit 1
  }
done

assert_contains() {
  local file=$1
  local text=$2
  grep -Fq -- "$text" "$repo_root/$file" || {
    printf '%s is missing required text: %s\n' "$file" "$text" >&2
    exit 1
  }
}

assert_absent() {
  local file=$1
  local text=$2
  if grep -Fq -- "$text" "$repo_root/$file"; then
    printf '%s retains retired text: %s\n' "$file" "$text" >&2
    exit 1
  fi
}

assert_contains README.md '## Documentation map'
assert_contains NEXT-STEPS.md 'Open work only'
assert_contains PROMPTS-HOMELAB.md '# Historical Implementation Prompts'
assert_contains K8S-CLUSTER-GUIDE.md 'Future design, not an executed runbook'
assert_contains SETUP.md 'POST /api/ingest/articles'
assert_contains SETUP.md 'AGENT_MODEL_ALIAS=worker'

assert_absent NEXT-STEPS.md 'GHCR package visibility is unconfirmed'
assert_absent SETUP.md 'POST /api/articles'
assert_absent SETUP.md 'AGENT_MODEL_ALIAS=planner'
assert_absent CLAUDE.md '## Current State / Roadmap'
assert_absent CLAUDE.md 'nightly backup (also in cron)'

while IFS= read -r target; do
  [[ -e "$repo_root/$target" ]] || {
    printf 'README local link target does not exist: %s\n' "$target" >&2
    exit 1
  }
done < <(sed -nE 's/.*\]\(([^)#]+)(#[^)]*)?\).*/\1/p' "$repo_root/README.md")

printf 'Documentation contract verified\n'
