# CLAUDE.md - homelab

## What This Repo Is

Infrastructure-as-config for Camp's homelab. It defines the Docker Compose stack running in the `docker-core` LXC (CT 110) on a single Proxmox node, the KAMRUI Pinova P1 (AMD R2544, 2 cores, 16GB RAM, 256GB SSD). This is an operations repo: compose files, service configs, runbooks, and Claude Code prompt sequences. Application code lives elsewhere (see Related Repos).

Domain: **camptwright.com**, DNS on Cloudflare. Public entry is exclusively via a named Cloudflare tunnel (`kamrui`); admin surfaces sit behind Cloudflare Access restricted to one email. There is no port forwarding and never will be.

## Files

```
docker-compose.yml     the whole stack, organized by compose profiles
.env                   secrets + settings (NEVER commit; .env.example is the contract)
.env.adjutant          Adjutant's env contract (consumed by the adjutant profile)
litellm-config.yaml    model alias map (fast/worker/planner/embed)
postgres-init.sql      first-boot DB/user creation (placeholder passwords;
                       SETUP.md A5 rotates them from .env via ALTER USER)
SETUP.md               the runbook: tonight path, per-service build-out,
                       existing-app integration, extras, future-node plans
PROMPTS-HOMELAB.md     Claude Code prompt sequences (dashboard A1-A7,
                       adjutant deploy B1, future-node stubs F1-F2)
K8S-CLUSTER-GUIDE.md   the future: Proxmox cluster + k3s when HP nodes arrive
```

## Architecture Rules (do not violate)

1. **Profiles are the deployment unit.** `core` (postgres, redis, litellm, cloudflared, ntfy, ollama-embed), `apps` (dashboard, miniflux, uptime-kuma, linkding, beszel + agent), `adjutant`, `extras`, `media` (future, wrong host: Jellyfin belongs on a future Intel node with Quick Sync, not this AMD box). `COMPOSE_PROFILES=core,apps` is set in .env; always pass or export profiles such that dependencies are in scope, or compose fails with "depends on undefined service".
2. **One shared Postgres** (pgvector/pgvector:pg16) serves adjutant, dashboard, and miniflux as separate databases/users. New services get a new database + user added to postgres-init.sql AND a matching ALTER USER line in SETUP.md A5. No service gets the postgres superuser.
3. **Every service has a mem_limit.** The host has 16GB shared with the Proxmox host and three other LXCs (wedding platform, Fantasy Edge, Los Ebanitos). The RAM budget table in SETUP.md is the ledger; update it when adding services. If a new service pushes the docker-core total past ~10GB steady-state, something else moves or the service waits for the cluster.
4. **All LLM traffic goes through LiteLLM** (`http://litellm:4000/v1` in-network, `http://<lxc-ip>:4000/v1` from other LXCs like OpenClaw). Services reference aliases (fast/worker/planner/embed), never provider model names or API keys. The GPU-node cutover must remain a litellm-config.yaml-only change.
5. **Access covers admin surfaces only.** In Access: admin, rss, status, links, beszel. Deliberately NOT in Access: ntfy (its phone app cannot complete a browser login; it uses its own deny-all + user auth) and any public site (wedding, Los Ebanitos). When adding a tunnel hostname, decide which bucket it belongs to and add it to the Access app if admin.
6. **Secrets live in .env only.** Anything committed must reference `${VARS}`. New variables get a documented line in .env.example.
7. **cloudflared reaches services by compose service name** (e.g. `uptime-kuma:3001`). Tunnel public-hostname URLs must not include a scheme prefix in the URL field (the Type dropdown supplies it) and must match compose service names exactly.

## Operational Lessons (learned the hard way; keep true)

- `beszel-agent` uses `network_mode: host` and therefore cannot inherit the `&small` anchor (which sets `networks:`). It is written out longhand. Do not "clean this up".
- Postgres healthcheck has `start_period: 90s` because first init on 2 cores exceeds the default budget. Keep it.
- The A5 password rotation requires `source .env` in the same shell first; running the ALTER USER block with unset vars CLEARS the passwords (postgres treats empty string as "remove password"). The runbook's echo sanity check exists for this reason.
- The `dashboard` service sits in profile `pending` until its image exists on GHCR (a missing GHCR image returns "denied", and one failed pull interrupts every parallel pull in the same `up`). Flip to `apps` after Prompt A1's first successful Actions build, and either make the package public or `docker login ghcr.io` on the LXC.
- Wiping `homelab_pgdata` is the correct fix for a failed FIRST init only. Once real data exists, never suggest volume removal as a fix; restore from the nightly pg_dumpall instead.
- **`net0` must be `ip6=auto`, never `ip6=dhcp`.** With `ip6=dhcp`, `ifup` blocks on a DHCPv6 Solicit that nothing on this LAN answers; `networking.service` hits its start timeout, is killed, and eth0 never gets its **IPv4** lease either. Symptom: `ip route` shows only the docker bridges, `ping` says "Network is unreachable", and every container logs `[Errno -3] Temporary failure in name resolution`. Fix: `pct set 110 -net0 ...,ip6=auto,...` then `systemctl restart networking` (Proxmox rewrites `/etc/network/interfaces` on config change).
- **Docker is nested in an unprivileged LXC, so the cgroup OOM event never reaches Docker.** A memory-killed container reports `OOMKilled=false`, and `docker inspect` can even show `ExitCode=0` because it races the restart. The only reliable signal is running the service in the foreground (`docker compose up <svc>`, no `-d`) and reading the real exit code: **137 = 128+9 = SIGKILL = out of memory**. Do not trust the `OOMKilled` flag on this host.
- LiteLLM needs ~1.07GB steady-state to hold six models plus the router, so its `mem_limit` is 1536m. At 512m it SIGKILLed mid-startup and crash-looped (6353 restarts) while logging nothing.
- **Editing `.env` does not affect running containers.** Compose injects environment at container *creation*; a service started before a value was filled in keeps the old (often empty) value forever. Miniflux crash-looped on `password authentication failed` while `psql` with the same credentials succeeded, because its container had an empty password baked in. Fix: `docker compose --profile core --profile apps up -d --force-recreate <svc>`.
- `docker compose exec -T` **consumes stdin**. Inside a piped script (`ssh host 'bash -s' < script`) it silently swallows the rest of the script. Always append `</dev/null` to `exec`/`run` calls in remote runbook scripts.

## Conventions for Changes

- Compose edits: keep the `&small` anchor pattern, profiles, and mem_limits. Validate before handing back: the file must parse (`docker compose config`) with core+apps profiles active.
- Runbook edits: SETUP.md is written as numbered, copy-pasteable steps with verification after every stage. Match that style. When a step has a failure mode we have hit, document the symptom and fix inline.
- New services: add to docker-compose.yml (right profile, mem_limit, logging via the anchor), .env.example if configurable, a tunnel hostname + Access decision per rule 5, an Uptime Kuma monitor note in SETUP.md, and the RAM ledger.
- Never add: port forwarding, host-network services (beszel-agent is the one exception), services storing secrets in images, or anything that bypasses LiteLLM for LLM calls.

## Related Repos

- `adjutant` - the agent system (orchestrator, sub-agents). Its PROMPTS.md 1-9 build Phase 1; PROMPTS-HOMELAB.md B1 adds its container deploy; K8S-CLUSTER-GUIDE Prompt 13 adds K8s manifests later.
- `homelab-dashboard` - Next.js admin dashboard behind Cloudflare Access (created by Prompt A1; tiles A2-A7).
- `camptwright.github.io` - public portfolio (GitHub Pages, static). The admin dashboard is intentionally NOT part of it; the portfolio may link to admin.camptwright.com at most.

## Dev/Ops Commands

```bash
cd /opt/homelab
docker compose up -d                      # COMPOSE_PROFILES=core,apps via .env
docker compose ps                         # health overview
docker compose logs <svc> --tail 30       # first move for any failure
docker compose config >/dev/null          # validate after editing compose
docker compose pull <svc> && docker compose up -d <svc>   # update one service
docker compose exec postgres psql -U postgres             # DB shell
# nightly backup (also in cron):
docker compose exec -T postgres pg_dumpall -U postgres | gzip > /opt/backups/pg-$(date +%F).sql.gz
```

## Current State / Roadmap

- DONE: core + apps running on the KAMRUI; tunnel + Access verified on camptwright.com; Kuma/Beszel/ntfy initialized. `dashboard` image is published and the service is live in profile `apps`.
- DONE: **LLM routing is local-first.** `fast` -> `qwen2.5:7b-instruct` and `worker` -> `qwen2.5:14b-instruct` run on the gaming PC (Ollama-ROCm, `http://10.51.24.9:11434`), with `fast-cloud`/`worker-cloud` Anthropic fallbacks and router cooldowns. `planner` is always cloud. `embed` -> the `ollama-embed` CPU sidecar on the KAMRUI, verified returning 768-dim vectors; that stays local permanently so pgvector memories remain comparable and memory writes never depend on the PC being awake.
- **BLOCKED: `ANTHROPIC_API_KEY` is empty in `.env`.** `planner` therefore 401s on every call, and the `fast-cloud`/`worker-cloud` fallbacks cannot fire - if the gaming PC sleeps, `fast` and `worker` fail outright with no safety net. Setting this key is the highest-value single fix outstanding.
- NEXT: set `ANTHROPIC_API_KEY`; then Adjutant Phase 1 (its repo, prompts 1-9) -> Prompt B1 -> `--profile adjutant`. `.env.adjutant` is already prepared on the LXC (its `API_BEARER_TOKEN` matches `ADJUTANT_API_TOKEN` in `.env`); it still needs a hand-made Proxmox API token (PVEAuditor) and, optionally, Telegram credentials.
- THEN: morning briefing schedule, OpenClaw ingest wiring, Fantasy Edge re-IP + monitoring. Miniflux needs first login (user `camp`, password in `.env` as `MINIFLUX_ADMIN_PASSWORD`) then an API key into `MINIFLUX_TOKEN`; Beszel needs its agent key into `BESZEL_AGENT_KEY`.
- FUTURE: HP EliteDesk nodes -> K8S-CLUSTER-GUIDE.md + Prompt F1 migration; custom AI node -> Prompt F2 LiteLLM cutover; Jellyfin on an Intel node.