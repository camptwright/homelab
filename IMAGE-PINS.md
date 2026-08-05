# Container Image Pins

Every production-capable Compose image is written as `tag@sha256:digest`. The
tag keeps the intended release channel readable; the digest makes deployments
and rollbacks immutable. For images built in Camp's repositories, the tag is
the full `sha-<git-commit>` tag emitted by GitHub Actions.

The pins captured on 2026-08-05 match the image objects already running on
CT110. Applying this file therefore does not require a restart: the next normal
recreation will use the same bytes through the immutable reference.

## Pending exception

`ghcr.io/camptwright/wellthread-web:latest` is the sole allowed exception. The
package currently returns `403 Forbidden` to anonymous manifest inspection and
the service is isolated in profile `pending`, so it is not part of production.
Once its first public image exists, replace `latest` with its source-SHA tag and
digest, move the service to `apps`, and remove the exception from
`tests/test-image-pins.sh` in the same commit.

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
