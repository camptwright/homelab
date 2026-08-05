# Documentation Consolidation Design

## Problem

The repository has no README and spreads current state across `CLAUDE.md`,
`NEXT-STEPS.md`, `SETUP.md`, and historical build prompts. Those copies have
drifted: GHCR is described as unavailable after it was fixed, Adjutant is
described with two agents instead of three, mutable image commands remain after
digest pinning, and the Access instructions incorrectly include ntfy.

## Ownership

- `README.md`: canonical current architecture, service inventory, daily
  operations, deployment caveats, and documentation map.
- `NEXT-STEPS.md`: unfinished work only, in priority order.
- `SETUP.md`: rebuild/provisioning and recovery reference.
- `IMAGE-PINS.md`: container update and rollback policy.
- `PROMPTS-HOMELAB.md`: historical implementation archive, not a runbook.
- `K8S-CLUSTER-GUIDE.md`: unexecuted future hardware plan.
- `CLAUDE.md`: durable architecture rules, operational lessons, and concise
  pointers to the canonical current-state documents.

## Verification

Claims are checked against Compose, environment examples, application routes,
Adjutant agent registrations/migrations, GitHub package pull results, CI, and
the live CT110 service state. Documentation links and stale phrases receive
automated contract tests so the ownership model cannot immediately drift back.
