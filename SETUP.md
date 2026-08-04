# SETUP.md - Homelab on the KAMRUI, Tonight

Everything runs on the KAMRUI Pinova P1 (2C/16GB/256GB) under Proxmox. Structure is deliberately migration-ready: when the HP nodes arrive, the compose stack lifts onto k3s (K8S-CLUSTER-GUIDE.md); when the GPU node arrives, one LiteLLM config edit moves inference local.

**Repo layout expected:**
```
homelab/            this repo: docker-compose.yml, .env, litellm-config.yaml,
                    postgres-init.sql, SETUP.md, PROMPTS-HOMELAB.md
adjutant/           the agent system (its own repo, PROMPTS.md 1-9)
homelab-dashboard/  admin dashboard (created by Prompt A1)
```

---

## Part A - Tonight (60-120 min to a working stack)

### A0. Prerequisites check

- [ ] Own router installed (Part 0.5 of the cluster guide). If it has not arrived, you can still do everything tonight on the apartment network EXCEPT you must skip static IPs (use DHCP + hostname) and accept that LAN access may fight client isolation. Cloudflare-tunneled access works regardless, since tunnels are outbound-only.
- [ ] A real domain with DNS on Cloudflare (free plan). You have GoDaddy; either move just the nameservers to Cloudflare (registration stays at GoDaddy, 10 minutes, free) or transfer fully. Quick Tunnels (trycloudflare URLs) cannot carry Cloudflare Access, so the wedding-site pattern is not enough here.
- [ ] Anthropic API key with billing enabled.

### A1. Create the docker LXC on Proxmox

Proxmox UI > Create CT:

| Setting | Value |
|---|---|
| Template | debian-12-standard |
| CT ID / hostname | 110 / `docker-core` |
| Cores / RAM / Swap | 2 / 12288 MB / 2048 MB |
| Disk | 120 GB (leave the rest of the SSD for existing LXCs + snapshots) |
| Network | static IP on YOUR router's subnet, e.g. 10.89.0.20/24 |
| Options after create | Features: **nesting=1** (required for Docker) |

Cores are shared with the other LXCs; that is fine, CPU is time-sliced. The 12GB RAM cap protects the wedding/Fantasy Edge LXCs and the Proxmox host.

### A2. Install Docker inside the LXC

```bash
apt update && apt -y upgrade
apt -y install curl git ca-certificates
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version
```

### A3. Clone and configure

```bash
mkdir -p /opt && cd /opt
git clone https://github.com/camptwright/homelab.git && cd homelab
cp .env.example .env
# fill .env; generate every password with: openssl rand -hex 24
```

### A4. Cloudflare tunnel + Access (the "only me" guarantee)

1. Cloudflare dashboard > your domain > confirm DNS is active on Cloudflare.
2. **Zero Trust > Networks > Tunnels > Create tunnel** (Cloudflared type), name it `kamrui`. Copy the token into `CLOUDFLARE_TUNNEL_TOKEN` in .env.
3. Add **Public Hostnames** on the tunnel (all pointing into the docker network by service name, which works because cloudflared runs inside the same compose network):
   | Hostname | Service |
   |---|---|
   | `admin.<domain>` | `http://dashboard:3000` |
   | `rss.<domain>` | `http://miniflux:8080` |
   | `status.<domain>` | `http://uptime-kuma:3001` |
   | `links.<domain>` | `http://linkding:9090` |
   | `ntfy.<domain>` | `http://ntfy:80` |
   | `beszel.<domain>` | `http://beszel:8090` |
4. **Zero Trust > Access > Applications > Add application** (Self-hosted):
   - Application domain: `admin.<domain>` (repeat this step for each hostname above; you can reuse one policy group)
   - Policy: Allow, Include > Emails > your Gmail. Nothing else.
   - Identity provider: the default one-time PIN works tonight; add Google login (Settings > Authentication) when convenient.
5. Open the application's **Overview** page and copy the **Application Audience (AUD) tag** into `CF_ACCESS_AUD`, and your team domain (`<team>.cloudflareaccess.com`) into `CF_ACCESS_TEAM_DOMAIN`. The dashboard verifies the Access JWT on every request with these; that is what makes the login real rather than decorative, even if someone reaches the container some other way.

### A5. Launch core + apps

```bash
docker compose --profile core --profile apps up -d
docker compose ps    # everything healthy/running

# one-time: replace init-script placeholder DB passwords with the .env values
source .env
docker compose exec postgres psql -U postgres -c \
 "ALTER USER adjutant PASSWORD '${ADJUTANT_DB_PASSWORD}';
  ALTER USER dashboard PASSWORD '${DASHBOARD_DB_PASSWORD}';
  ALTER USER miniflux PASSWORD '${MINIFLUX_DB_PASSWORD}';
  ALTER USER wellthread PASSWORD '${WELLTHREAD_DB_PASSWORD}';
  ALTER USER authenticator PASSWORD '${AUTHENTICATOR_PASSWORD}';
  ALTER USER supabase_auth_admin PASSWORD '${AUTH_ADMIN_PASSWORD}';"
docker compose restart miniflux
```

Verify from any browser, anywhere: `https://status.<domain>` should demand your email PIN/Google login, then show Uptime Kuma's setup screen. That round trip proves tunnel + Access + stack in one shot.

### A6. Tailscale (LAN access from anywhere, no tunnel needed)

On the **Proxmox host** (simplest; survives any LXC rebuild):

```bash
curl -fsSL https://tailscale.com/install.sh | sh
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf && sysctl -p /etc/sysctl.d/99-tailscale.conf
tailscale up --advertise-routes=10.89.0.0/24   # your private subnet
```

Approve the route in the Tailscale admin console, install Tailscale on laptop + phone. Now the Proxmox UI, LXC SSH, and every service's LAN port are reachable from anywhere. Tunnel = public-ish (Access-gated) browser access; Tailscale = full private network access. Keep both.

### A7. First-login checklist (10 min)

- **Uptime Kuma** (`status.<domain>`): create admin, add monitors: dashboard, rss, the wedding site URL, Los Ebanitos URL, Fantasy Edge health endpoint, `ntfy.<domain>`, marketdesk's `http://marketdesk:8000/health` (internal-only, no tunnel hostname - same docker network as Kuma itself).
- **ntfy**: `docker compose exec ntfy ntfy user add --role=admin camp`, subscribe to topic `homelab` in the phone app. Point Uptime Kuma notifications at `https://ntfy.<domain>/homelab`. Your infrastructure can now buzz your pocket.
- **Miniflux** (`rss.<domain>`): log in (camp / MINIFLUX_ADMIN_PASSWORD), Settings > API keys > create, put it in `.env` as `MINIFLUX_TOKEN`. Add starter feeds: Hacker News frontpage, r/homelab and r/selfhosted (reddit .rss URLs), Simon Willison, the Self-Host newsletter, Anthropic news, Texas A&M MSAI announcements if they publish a feed.
- **Beszel** (`beszel.<domain>`): create admin, Add System > localhost:45876, copy the key into `BESZEL_AGENT_KEY` in .env, `docker compose up -d beszel-agent`. CPU/RAM/disk/docker stats per container, at a fraction of Grafana's weight.
- **Linkding** (`links.<domain>`): log in, install the browser extension, done.

**Tonight's stack is complete here.** Parts B-E are the build-out.

---

## Part B - Service Build-Out

### B1. Admin dashboard shell

Run **Prompt A1** (PROMPTS-HOMELAB.md) in a new `homelab-dashboard` repo, push, let Actions build the image, then:

```bash
docker compose pull dashboard && docker compose up -d dashboard
```

`admin.<domain>` is now your private front door. Every following feature is a tile in it.

### B2. Adjutant on the KAMRUI

Adjutant (`github.com/camptwright/adjutant`) is a single container: FastAPI
+ an in-process APScheduler reading its cron jobs from the `schedules`
table, no Celery/Redis/worker/beat processes. Two agents exist today:
`infra` (reads Uptime Kuma's public status page) and `markets` (reads
marketdesk, posts briefs to the dashboard).

1. `adjutant` role/database already exist in `postgres-init.sql`. Rotate
   the placeholder password the same way as any other service (A5
   pattern): `source .env` then `ALTER USER adjutant WITH PASSWORD
   '$ADJUTANT_DB_PASSWORD';`.
2. Create/verify `.env.adjutant` next to docker-compose.yml:
   ```
   DATABASE_URL=postgresql+asyncpg://adjutant:<pw>@postgres:5432/adjutant
   API_BEARER_TOKEN=<same as ADJUTANT_API_TOKEN in .env>
   LITELLM_BASE_URL=http://litellm:4000/v1
   LITELLM_API_KEY=<same as .env>
   AGENT_MODEL_ALIAS=planner
   MARKETS_URL=http://marketdesk:8000
   MARKETS_API_TOKEN=<same as MARKETS_API_TOKEN in .env>
   DASHBOARD_INGEST_URL=http://dashboard:3000/api/ingest/articles
   ARTICLE_INGEST_TOKEN=<same as ARTICLE_INGEST_TOKEN in .env>
   UPTIME_KUMA_STATUS_URL=https://status.<domain>/api/status-page/<slug>
   ```
   `PROXMOX_TOKEN_ID`/`PROXMOX_TOKEN_SECRET` (Datacenter > Permissions >
   API Tokens, `PVEAuditor` role only) are for a future infra tool beyond
   Uptime Kuma - not consumed by anything yet, so skip them for now.
3. `docker compose --profile core --profile apps --profile adjutant up -d` then run migrations once (creates `tasks`/`runs`/`approvals`/`schedules` and seeds `premarket_brief`/`portfolio_recap`):
   `docker run --rm --network homelab_homelab -e DATABASE_URL=... ghcr.io/camptwright/adjutant:latest alembic upgrade head`
4. Smoke test: `curl -H "Authorization: Bearer $ADJUTANT_API_TOKEN" -d '{"goal":"Are any homelab services down?"}' http://<lxc-ip>:8000/task` (or through the dashboard's Adjutant tile Submit form), then check `/tasks/{id}` for a `completed` status and a real `Run` row.

### B3. Morning briefing page

Two pieces, both tiny once B1 + B2 exist:

1. Adjutant side: register a new agent (or add a `miniflux_unread` tool to
   `infra`, see adjutant repo's `src/agents/`) that calls the Miniflux API
   (`/v1/entries?status=unread&limit=30`, token header), then seed a
   schedule row (real column names - `schedules` has `name`/`cron`/`agent`/
   `goal`/`enabled`, see adjutant's `alembic/versions/0002` for the exact
   pattern the markets schedules use):
   ```sql
   INSERT INTO schedules (name, cron, agent, goal) VALUES
   ('morning_briefing', '30 6 * * 1-5', 'briefing',
    'Write the morning briefing: 5-8 top items from unread RSS with one-line
     takes, homelab health summary, and anything unusual from yesterday''s
     agent runs. Then mark included RSS items read. Post the briefing to the
     dashboard articles API with source=briefing.');
   ```
2. Dashboard side: Prompt A3's briefing tile renders the latest `source=briefing` article at the top of the dashboard. Coffee, one page, done.

### B4. OpenClaw article archive

The dashboard exposes `POST /api/articles` (bearer `ARTICLE_INGEST_TOKEN`, JSON: title, body_markdown, source, tags). Wiring OpenClaw:

1. Point your OpenClaw instance's model config at LiteLLM (`http://<kamrui-ip>:4000/v1`) so its usage rides the same aliases and shows in the same spend accounting.
2. Wherever OpenClaw's write-up job runs (cron/heartbeat), end it with:
   ```bash
   curl -s -X POST https://admin.<domain>/api/articles \
     -H "Authorization: Bearer $ARTICLE_INGEST_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$(jq -n --arg t "$TITLE" --arg b "$BODY" \
          '{title:$t, body_markdown:$b, source:"openclaw", tags:["daily"]}')"
   ```
   (Access is bypassed for this route via a service-token rule, or simpler: also publish the ingest route on a separate hostname `ingest.<domain>` with a Cloudflare Access **Service Auth** policy. Prompt A4 covers validating either.)
3. Prompt A4's archive tile gives you the searchable private blog of everything OpenClaw and Adjutant write. Same table, `source` column distinguishes the authors, which makes comparing their takes on the same news a standing amusement.

### B5. Finance snapshot

Phase-able, safe by construction (nothing can move money):

- **Tonight-level:** Prompt A5 builds a tile with CSV upload (bank/card exports), a categorizer that calls the `fast` alias for uncategorized merchants, monthly category chart, savings-rate trend, and an anomalies list. Data stays in the dashboard DB on your hardware.
- **Later:** Adjutant's Phase 3 Finance agent reads the same tables and the briefing starts including "you're 40% through the dining budget and it's the 9th."
- **Alternative/complement:** Actual Budget (extras profile) is a full envelope-budgeting app; if you find you want budgeting workflow rather than passive snapshots, turn it on and let the tile read its SQLite export instead of reinventing it.

### B6. Grad school tracker

Prompt A6: courses table (MSAI course code, name, term), deadlines with type (assignment/exam/registration), a compact kanban (todo/doing/done), and an ICS export URL you can subscribe to from Google Calendar. Seed it with the August term as soon as syllabi drop. The briefing job includes "due in the next 7 days" once this exists.

### B7. Embedding sidecar (needed before Adjutant Phase 2)

Adjutant's memory layer wants `nomic-embed-text` at 768 dims. CPU is fine for embeddings even on the R2544:

```yaml
# add under services:, profile [core]
  ollama-embed:
    <<: *small
    profiles: [core]
    image: ollama/ollama:latest
    volumes: [ollamaembed:/root/.ollama]
    mem_limit: 1024m
```
```bash
docker compose up -d ollama-embed
docker compose exec ollama-embed ollama pull nomic-embed-text
```
(litellm-config.yaml already routes the `embed` alias here.)

### B8. Fantasy cockpit

Prompt A7 proxies the Fantasy Edge API through the dashboard (server-side, using `FANTASY_EDGE_URL`, so nothing about your betting-value data is exposed beyond Access). Tiles: current roster, this week's top probability edges, bet_signals output, and the Fantasy agent's weekly report once Phase 3 lands. Season note: drafts are in August; prioritize this tile in early August.

---

## Part C - Existing Apps Integration

### C1. Fantasy Edge (existing LXC)

1. After the router lands, re-IP the LXC onto your subnet (one interface edit in Proxmox + inside the guest). Update `FANTASY_EDGE_URL` in .env.
2. Add its `/health` (add one if absent) to Uptime Kuma with ntfy alerts. Sundays are not the day to discover Celery died Thursday.
3. Point its Redis/Postgres nowhere new; it keeps its own stack. Consolidation onto the shared postgres is optional future cleanup, not tonight work.
4. Register it as a tool target for the Infra agent (hosts map in `.env.adjutant`) so "why is Fantasy Edge slow" works.

### C2. Wedding photo platform (existing LXC)

1. Migrate its Cloudflare **Quick** Tunnel to the named `kamrui` tunnel: add a public hostname `wedding.<domain>` (or keep a separate named tunnel in that LXC if you prefer isolation; either beats an ephemeral trycloudflare URL that changes on restart).
2. **No Access policy on it.** Guests need anonymous access. Access is for admin surfaces only.
3. Uptime Kuma monitor + a Beszel agent in the LXC (one binary) so the photo upload spike on event day is visible.

### C3. Los Ebanitos Ranch site

If it is static (marketing site): consider moving hosting to Cloudflare Pages (free, global CDN, deploys from the GitHub repo on push) and retiring its LXC entirely; the KAMRUI's RAM is better spent elsewhere. If it has server-side pieces, treat it exactly like C2: named tunnel hostname, no Access, monitor it.

---

## Part D - Extras Worth Turning On (researched, ranked)

Turn on with `docker compose --profile extras up -d <service>` where included, or add per the notes.

| Rank | Tool | Why for you specifically | Cost |
|---|---|---|---|
| 1 | **Vaultwarden** (in compose) | Self-hosted Bitwarden server; all official clients work. Once you have a domain + tunnel, this is the highest-value 15 minutes in self-hosting. Backup its volume religiously. | ~150MB RAM |
| 2 | **Paperless-ngx** (add later) | OCR + search for every PDF in your life: apartment lease, car docs, Lockheed paperwork, MSAI enrollment. Wants ~1GB RAM + a Redis; viable on KAMRUI, great on an HP node. | ~1GB |
| 3 | **Karakeep** (formerly Hoarder) | AI-tagging bookmarks/read-later; can point its LLM calls at your LiteLLM proxy. Overlaps Linkding; pick one after trying both (Karakeep is heavier: needs Meilisearch + Chrome container). | ~1.5GB |
| 4 | **WhoDB** (in compose) | Lightweight DB admin for the shared postgres with natural-language querying and an MCP mode, so Claude can inspect your databases. Handy while building the dashboard. | ~200MB |
| 5 | **ntfy** (already in core) | Push notifications from anything that can curl. Wire Uptime Kuma, Adjutant AUTO-tier notifications, and cron jobs to it. | ~50MB |
| 6 | **Actual Budget** (in compose) | Full budgeting workflow to complement the passive finance tile. | ~200MB |
| 7 | **Immich** (HP-node future) | Google Photos replacement, genuinely excellent, but wants 4GB+ RAM and real storage. Queue it for the cluster; do not squeeze it onto the KAMRUI. | heavy |
| 8 | **Home Assistant** (future, if smart-home) | Run as a VM (HAOS) on an HP node, not a container; the container variant loses the add-on ecosystem. Only if you accumulate smart devices. | heavy |
| 9 | **Pinchflat** | Auto-archives YouTube channels/playlists to disk; pairs with Jellyfin later. | ~300MB |
| 10 | **Pocket ID** (future polish) | Self-hosted passkey SSO; one login for every service instead of per-app passwords, once you outgrow Cloudflare Access alone. | light |

Skip for now: Nextcloud (heavy; Syncthing or plain SMB covers file sync at your scale), Plex (Jellyfin won), Grafana/Prometheus stacks (Beszel + Uptime Kuma cover a 1-node lab; revisit on the cluster with kube-prometheus-stack where it doubles as K8s learning).

---

## Part E - Future Nodes (the plan is already shaped for this)

### E1. When the HP EliteDesks arrive

1. Follow K8S-CLUSTER-GUIDE.md Parts 1-6 (the KAMRUI joins the Proxmox cluster as pve-svc; this LXC keeps running through all of it).
2. Migrate in dependency order: CNPG postgres first (pg_dump each DB from the compose postgres, restore into the cluster), then Adjutant via Prompt 13 (K8s manifests), then the dashboard (same pattern), then apps (each is a one-Deployment lift; or leave the light ones on the KAMRUI forever, it is a fine services box).
3. Jellyfin goes on an HP node with `/dev/dri` passed for Quick Sync. Media on a USB/SATA disk or a NAS-later decision.
4. The `media` profile and the future-node comments in this repo are the breadcrumbs; PROMPTS-HOMELAB.md has the migration prompt stubs.

### E2. When the custom AI node arrives

1. Joins Proxmox as pve-gpu; Ubuntu VM with 3090 passthrough running Ollama.
2. Edit litellm-config.yaml: swap `fast`/`worker` (and `embed`, retiring the CPU sidecar) to the Ollama blocks, `docker compose restart litellm` (or rollout restart if LiteLLM has moved to K8s by then).
3. Nothing else in any repo changes. Watch the Anthropic line item on the dashboard's spend tile drop to just `planner` calls.

---

## RAM Budget (KAMRUI, 16GB)

| Consumer | Budget |
|---|---|
| Proxmox host | ~1.5GB |
| Existing LXCs (wedding, Fantasy Edge, Los Ebanitos) | ~3GB |
| docker-core LXC cap | 12GB, of which: |
| core (pg 1536 + redis 384 + litellm 1536 + cloudflared 128 + ntfy 128 + ollama-embed 1024) | ~4.6GB |
| apps (dashboard 512 + miniflux 256 + kuma 384 + linkding 256 + beszel 128 + agent 64 + marketdesk 384) | ~2GB |
| wellthread (auth 192 + rest 256 + gateway 64 + web 512) | ~1GB |
| adjutant (single container, no Celery/Redis) | ~0.5GB |
| extras (vaultwarden + whodb + actual, 256 each) | ~0.75GB |
| headroom | ~3.1GB |

Sum of `mem_limit` ceilings, not steady-state usage; actual draw is well under
this (measured: litellm ~1.07GB, ollama-embed ~0.37GB, everything else small).

Core grew from the original ~3.5GB estimate for two measured reasons: litellm
needs 1536m (it SIGKILLs at 512m - see CLAUDE.md operational lessons), and the
ollama-embed sidecar adds 1024m. Adjutant turning out to be a single
lightweight container rather than the originally-planned Celery 3-process
shape recovered ~1.5GB of that headroom. If memory pressure appears anyway:
Los Ebanitos to Cloudflare Pages (C3) and defer Karakeep/Paperless to the
cluster.

Watch list (measured against ceiling, flag at >80%): litellm ~71%, linkding
~74%. Neither is over yet, but both are close enough to check after any image
bump.

## Backups (do not skip)

- Proxmox: nightly vzdump of all LXCs to a USB disk (Datacenter > Backup).
- Postgres: nightly `pg_dumpall` cron inside docker-core to a directory included in vzdump:
  `docker compose exec -T postgres pg_dumpall -U postgres | gzip > /opt/backups/pg-$(date +%F).sql.gz`
- Vaultwarden volume: included in vzdump automatically, but test a restore once before trusting it with passwords.
