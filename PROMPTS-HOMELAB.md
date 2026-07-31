# PROMPTS-HOMELAB.md - Claude Code Build Sequence

Prompts A1-A7 build the admin dashboard (new repo `homelab-dashboard`).
Prompt B1 runs in the `adjutant` repo. F1-F2 are future-node stubs.
Run in order; A2-A7 can be reordered after A1. Commit between prompts.

---

## Prompt A1 - Dashboard Shell

```
Create a Next.js 15 (App Router, TypeScript, Tailwind) project called
homelab-dashboard: a private single-user admin dashboard that runs behind
Cloudflare Access. Dark theme, Inter, glass-morphism cards, consistent with
a modern minimal aesthetic. Mobile-responsive; this will be used from a
phone constantly.

Auth: middleware.ts verifies the Cf-Access-Jwt-Assertion header on EVERY
request (pages and API): fetch the signing keys from
https://${CF_ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs (cache 12h), verify
signature, expiry, and that the aud claim contains ${CF_ACCESS_AUD}. On
failure return 403 with no body. Exception: routes under /api/ingest/*
skip Access-JWT and instead require Authorization: Bearer
${ARTICLE_INGEST_TOKEN} (constant-time compare). There is no login page;
Cloudflare is the login page.

Data: Postgres via drizzle-orm using DATABASE_URL. Create a tiles registry
pattern: each tile is a self-contained module under src/tiles/<name>/ with
a server component, optional API routes, and a manifest (title, size,
refresh interval). The home page composes registered tiles in a responsive
grid. Ship two starter tiles: (1) system: calls the Beszel/Uptime Kuma
pattern later, for now shows a static placeholder; (2) quick-links:
configurable grid of links to rss./status./links./vault. subdomains read
from a JSON config.

Also: drizzle migrations setup with a migrate script, a multi-stage
Dockerfile (standalone Next output, non-root), .dockerignore, and a GitHub
Actions workflow pushing ghcr.io/camptwright/homelab-dashboard:latest and
:sha-<sha> on main. Healthcheck route /api/health (no auth) returning ok +
db connectivity. README with the env vars used.
```

## Prompt A2 - Adjutant Mission Control Tile

```
Add tile 'adjutant' to homelab-dashboard. Server-side only communication
with ${ADJUTANT_API_URL} using bearer ${ADJUTANT_API_TOKEN}; never expose
the token or the API to the browser (all through Next API routes).

Views within the tile (tabbed): (1) Submit: textarea posting a goal to
POST /task, showing the created task id; (2) Activity: recent tasks with
status chips, expandable to per-agent runs showing agent, model alias,
tokens, latency, and tool calls with args/results rendered as collapsible
JSON; auto-refresh every 10s while any task is non-terminal; (3) Approvals:
pending PROPOSE actions with the human-readable summary and Approve/Deny
buttons calling the corresponding Adjutant endpoints (add
POST /approvals/{id}/resolve to the Adjutant API if absent: note it in the
README as a required Adjutant-side addition); (4) Spend: tokens by model
alias by day for the last 30 days as a stacked bar chart (recharts),
computed from the runs endpoint.

Graceful degradation: if Adjutant is unreachable, the tile shows a quiet
offline state, never an error page.
```

## Prompt A3 - Briefing + Feeds Tile

```
Add tile 'briefing' to homelab-dashboard. Top section renders the most
recent article with source='briefing' from the articles table (created in
Prompt A4; if not yet built, create the articles schema now exactly as A4
specifies) as formatted markdown with a generated-at timestamp. Below it,
'Unread highlights': server-side call to ${MINIFLUX_URL}/v1/entries?
status=unread&limit=10&order=published_at&direction=desc with X-Auth-Token
${MINIFLUX_TOKEN}, rendered as compact rows (title, feed name, age) that
link to the entry and a 'mark read' button calling the Miniflux API.
Keep all Miniflux communication server-side.
```

## Prompt A4 - Article Archive (OpenClaw + Adjutant writings)

```
Add tile 'articles' plus a full page /articles to homelab-dashboard.

Schema (drizzle migration): articles(id uuid pk, title text, body_markdown
text, source text, tags text[], created_at timestamptz default now()),
with a GIN index for full-text search over title + body.

Ingest: POST /api/ingest/articles accepting {title, body_markdown, source,
tags?} under the ARTICLE_INGEST_TOKEN bearer described in A1. Validate
with zod; reject bodies over 200KB; return the created id.

UI: /articles lists newest-first with source badges (openclaw, briefing,
adjutant), tag filter chips, and full-text search. Article view renders
markdown safely (rehype-sanitize), with prev/next navigation. The tile on
the home page shows the 5 newest titles with source badges. Add an RSS
feed at /articles/feed.xml protected by Access like everything else, so
Miniflux (via its own cookie-less fetch, add a note that this requires a
Cloudflare service token header configured in Miniflux's feed settings)
can optionally re-ingest the archive.
```

## Prompt A5 - Finance Snapshot Tile

```
Add tile 'finance' plus page /finance to homelab-dashboard.

Schema: transactions(id, date, description, merchant, amount numeric,
category text, account text, import_batch uuid, created_at) and
category_rules(id, pattern text, category text, priority int).

Import: on /finance, a CSV upload (papaparse server-side) with a column-
mapping step supporting common bank/card export shapes; dedupe on
(date, description, amount, account). Categorization: apply category_rules
first; for remaining unknowns, batch-call the LiteLLM proxy
(${LITELLM_BASE_URL}, model 'fast', key ${LITELLM_API_KEY}) with merchant
strings, asking for one category each from a fixed list, and offer the
result as suggestions the user confirms; confirmed suggestions create new
category_rules so the system learns.

Views: monthly spend by category (stacked bars, 6 months), savings rate
line (income categories minus spend), top merchants table, and an
anomalies list (any transaction > 2x the 90-day median for its category).
No feature may modify anything outside these two tables; this is
read-and-reflect only.
```

## Prompt A6 - Grad School Tracker Tile

```
Add tile 'gradschool' plus page /school to homelab-dashboard.

Schema: courses(id, code, name, term, credits) and school_items(id,
course_id fk, title, type in ['assignment','exam','reading','registration',
'admin'], due_at timestamptz, status in ['todo','doing','done'], notes,
created_at).

UI: /school shows a term selector, a three-column kanban (todo/doing/done)
with drag-and-drop (dnd-kit) persisting status, and a deadline list view
sorted by due_at with overdue highlighted. Quick-add parses natural
strings like 'CSCE 625 HW2 due Sep 12' using a small deterministic parser
(no LLM). ICS export at /school/calendar.ics (Access-protected) containing
all non-done items with due dates, so Google Calendar can subscribe via
a Cloudflare service token URL (document how in the README). Home tile:
next 5 upcoming items with days-remaining badges.
```

## Prompt A7 - Fantasy Cockpit Tile

```
Add tile 'fantasy' plus page /fantasy to homelab-dashboard. All Fantasy
Edge communication is server-side against ${FANTASY_EDGE_URL}; assume
endpoints /health, /props, /probabilities, /signals and write a thin typed
client with per-endpoint 60s caching; where the real API differs, keep the
client isolated in one file and note the assumption in the README.

Views: current week's top probability edges (sortable table: player, prop,
line, model probability, implied probability, edge %), bet signals feed,
and a slot that renders the newest article with source='fantasy-agent'
(the future weekly start/sit report) when present. Home tile: top 3 edges
+ Fantasy Edge health dot. If Fantasy Edge is unreachable, quiet offline
state.
```

---

## Prompt B1 - Adjutant Compose Deployment (run in the adjutant repo)

```
Read CLAUDE.md. Add container deployment WITHOUT Kubernetes (that comes
later as Prompt 13):

1. Multi-stage Dockerfile: builder runs uv sync into a venv; runtime on
   python:3.12-slim, non-root user, entrypoint script selecting by first
   arg: api (uvicorn app.main:app --host 0.0.0.0 --port 8000), worker
   (celery -A app.scheduler worker --loglevel=info --concurrency=2), beat
   (celery -A app.scheduler beat).
2. .dockerignore and a GitHub Actions workflow pushing
   ghcr.io/camptwright/adjutant:latest and :sha-<sha> on main.
3. Ensure the FastAPI app reads API_BEARER_TOKEN and protects /task,
   /runs, /tasks/{id}, and add POST /approvals/{id}/resolve
   (body: {decision: 'approved'|'denied'}) updating the approvals row,
   for the dashboard's mission-control tile.
4. A short DEPLOY-COMPOSE.md documenting the .env.adjutant contract and
   the migration command
   (docker compose run --rm adjutant-api alembic upgrade head), matching
   the homelab repo's SETUP.md Part B2.
Keep worker concurrency at 2: the host has 2 cores shared with everything
else.
```

---

## Future Prompts (stubs; run when hardware arrives)

## Prompt F1 - Cluster Migration (HP nodes)

```
Context: k3s cluster now exists per K8S-CLUSTER-GUIDE.md. In the adjutant
repo run the guide's Prompt 13 (K8s manifests). Then in homelab-dashboard:
add k8s/ manifests mirroring the compose service (deployment, service,
configmap/secret contract, migration job) targeting namespace 'adjutant',
resource requests 100m/256Mi. In the homelab repo: write MIGRATION.md
covering pg_dump/restore of each database from the compose postgres into
the CNPG cluster, cutover order (postgres, adjutant, dashboard, apps), the
Cloudflare tunnel public-hostname updates from docker service names to
cluster LoadBalancer IPs, and rollback steps (the compose stack stays
intact until verified).
```

## Prompt F2 - GPU Node Cutover (AI node)

```
Context: pve-gpu exists with Ollama serving on the LAN. In the homelab
repo: update litellm-config.yaml swapping fast/worker/embed to the Ollama
blocks (worker model sized to VRAM: qwen2.5:32b-instruct-q4 for 24GB),
retire the ollama-embed sidecar from docker-compose.yml, and add a
CANARY.md procedure: run the Adjutant eval/smoke tasks with worker on
local for 3 days while planner stays on Anthropic, comparing failure
rates via the agent_runs table before removing the Anthropic fallback
blocks from the config.
```
