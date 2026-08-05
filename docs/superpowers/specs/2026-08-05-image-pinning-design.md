# Production Image Pinning Design

## Goal

Make the CT110 stack reproducible by preventing mutable registry tags from
silently changing deployed software.

## Contract

All Compose images use `tag@sha256:digest`. Existing deployed image digests are
the source of truth for active services, so adopting the pins changes no image
bytes. In-house images additionally use their immutable full source-commit tag.
Dormant public profiles are pinned to the registry manifest observed during the
same inventory.

The only exception is the inaccessible `wellthread-web` image in profile
`pending`. A test enforces that it remains the one and only exception.

## Operations

Pins are advanced one service at a time after release review, registry digest
resolution, Compose validation, targeted recreation, and health verification.
Git history is the rollback ledger. Merely pulling a mutable tag is not an
update procedure.

No healthy service is restarted when these initial pins are installed because
the referenced digests already match its running image object.
