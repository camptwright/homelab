# Homelab

Infrastructure-as-config for Camp's KAMRUI Pinova P1 homelab. The active stack
runs in Docker inside Proxmox LXC CT110 (`docker-core`). Public browser access
is exposed only through a named Cloudflare Tunnel. Administrative sites use
Cloudflare Access; ntfy deliberately uses its own authentication so its phone
client works. LiteLLM also listens on the private LAN for other LXCs.

This repository contains deployment configuration and runbooks. Application
code remains in its own repositories.

## Live architecture

| Profile | Services | State |
|---|---|---|
| `core` | PostgreSQL/pgvector, Redis, LiteLLM, cloudflared, ntfy, Ollama embeddings | Live |
| `apps` | dashboard, Miniflux, Uptime Kuma, Linkding, Marketdesk, Beszel hub/agent, Wellthread auth/REST/gateway | Live |
| `adjutant` | single FastAPI + APScheduler container | Live |
| `extras` | Vaultwarden, Actual Budget, WhoDB | Available, not enabled |
| `media` | Jellyfin | Future Intel/Quick Sync node |
| `pending` | Wellthread web | Disabled until its GHCR package exists |

The shared PostgreSQL instance has separate databases and roles for Adjutant,
the dashboard, Marketdesk, Miniflux, and Wellthread. LiteLLM is the only LLM
gateway: `fast` and `worker` are local-first, `planner` is cloud, and `embed`
uses the CT110 Ollama sidecar.

The three in-house application images—dashboard, Marketdesk, and Adjutant—are
public on GHCR and deployed successfully. Compose pins their source-commit tags
and every other production-capable image to immutable registry digests.

## Related repositories

- `homelab-dashboard`: private Next.js operations dashboard.
- `adjutant`: three-agent orchestrator (`infra`, `markets`, `fantasy`).
- `marketdesk`: read-only market data and portfolio API.
- `fantasy-edge`: separate CT100 sports/fantasy service consumed read-only by
  the dashboard and Adjutant.

The parent `homelab-master` repository pins tested revisions of these and the
other child repositories in `repos.lock`; each child retains its own Git
history and SSH remote.

## Daily operations

Run these inside CT110 from `/opt/homelab`:

```bash
docker compose --profile core --profile apps --profile adjutant ps
docker compose --profile core --profile apps --profile adjutant config --quiet
docker compose logs --tail 50 <service>
systemctl status homelab-postgres-backup.timer
/opt/homelab/scripts/restore-test-postgres.sh
```

Do not treat `docker compose pull` as an update mechanism. Images are
digest-pinned; follow [IMAGE-PINS.md](IMAGE-PINS.md) to review, pin, recreate,
verify, and roll back one service at a time.

Nightly PostgreSQL dumps are checksummed, retained for fourteen days, and
restore-tested in a disposable container. They still live on the same physical
host, so they are recovery staging—not disaster recovery—until USB or network
storage is available.

## Deployment checkout caveat

CT110's `/opt/homelab` is currently a live operational checkout with a local
commit and uncommitted configuration accumulated during bring-up. It is not a
clean deploy clone. Do not run `git reset`, `git checkout`, or a blind
`git pull` there. Preserve `.env` and `.env.adjutant`, inventory the local
changes, and reconcile it as the dedicated task in [NEXT-STEPS.md](NEXT-STEPS.md).
Until then, install reviewed configuration files individually after making a
recoverable backup and validating them in place.

## Documentation map

| Document | Authority |
|---|---|
| [README.md](README.md) | Current architecture, service state, daily operations |
| [NEXT-STEPS.md](NEXT-STEPS.md) | Unfinished work, ordered by priority |
| [SETUP.md](SETUP.md) | Provisioning, rebuild, and recovery reference |
| [IMAGE-PINS.md](IMAGE-PINS.md) | Container update and rollback procedure |
| [SECURITY.md](SECURITY.md) | Trust boundaries, mitigations, and accepted residual risk |
| [CLAUDE.md](CLAUDE.md) | Durable implementation rules and learned failure modes |
| [PROMPTS-HOMELAB.md](PROMPTS-HOMELAB.md) | Historical build prompts; not current instructions |
| [K8S-CLUSTER-GUIDE.md](K8S-CLUSTER-GUIDE.md) | Future, unexecuted multi-node plan |

## Validation

Pull requests and pushes to `main` run Bash behavior tests, ShellCheck, systemd
unit verification, environment-contract checks, digest-pin checks, and a full
Compose parse with safe example values.

```bash
bash -n scripts/*.sh tests/*.sh
bash tests/test-compose-env.sh
bash tests/test-docs-contract.sh
bash tests/test-image-pins.sh
bash tests/test-security-contract.sh
bash tests/test-backup-postgres.sh
bash tests/test-restore-postgres.sh
```
