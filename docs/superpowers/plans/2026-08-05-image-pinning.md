# Production Image Pinning Implementation Plan

**Goal:** Lock every production-capable Compose image to a reviewed immutable
digest without changing the currently deployed software.

## Tasks

- [x] Inventory active CT110 container tags, image IDs, and registry digests.
- [x] Resolve public registry manifests for dormant `extras` and `media` images.
- [x] Map in-house image digests to full source-commit tags in GitHub Packages.
- [x] Add a failing regression test for unpinned images with exactly one
  `wellthread-web` pending-profile exception.
- [x] Pin resolvable Compose images as `tag@sha256:digest`.
- [x] Add the pin test to GitHub Actions and document update/rollback policy.
- [ ] Validate Bash, Compose, and all repository tests locally and on CI.
- [ ] Install the committed Compose definition on CT110 without recreating the
  already healthy containers; verify runtime digests and health remain stable.
