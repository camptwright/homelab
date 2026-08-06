# Container Image Pins

Every production-capable Compose image is written as `tag@sha256:digest`. The
tag keeps the intended release channel readable; the digest makes deployments
and rollbacks immutable. For images built in Camp's repositories, the tag is
the full `sha-<git-commit>` tag emitted by GitHub Actions.

The pins captured on 2026-08-05 match the reviewed image objects. Wellthread
web's public source-SHA image was verified anonymously before its production
profile promotion. Applying a changed pin is a separate controlled operation;
this policy does not authorize recreating a live service.

## Updating one image

1. Read the release notes and choose the target tag; do not advance an entire
   profile as one unreviewed update.
2. Resolve the registry digest with
   `docker buildx imagetools inspect <image>:<tag>`.
3. Change only that service's `tag@sha256:digest`, then run:

   ```bash
   bash tests/test-image-pins.sh
   docker compose --env-file env.example --profile core --profile apps \
     --profile adjutant config --quiet
   ```

4. On CT110, pull and recreate only that service, preserving its required
   profiles and dependencies. Verify `docker compose ps`, its health endpoint,
   and recent logs before committing the new pin.
5. Commit the old-to-new pin change. Rolling back means reverting that commit,
   pulling the old digest if necessary, and recreating only the affected
   service.

Never use `docker compose pull` as an update policy by itself: a digest-pinned
reference intentionally remains unchanged until this review process advances
it.
