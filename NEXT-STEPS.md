# Next Steps

Open work only, ordered by operational value. Last verified 2026-08-05.
Completed architecture and service state belong in [README.md](README.md);
durable failure modes belong in [CLAUDE.md](CLAUDE.md).

## 1. Rotate credentials exposed during local hardening

On 2026-08-05, a production Compose validation command printed resolved
environment values into a private Codex task transcript. No values were
committed or pushed, but treat every credential in `.env` and `.env.adjutant`
as exposed to that transcript.

**Internal rotation complete (2026-08-06):** all 8 Postgres role passwords
(`POSTGRES_SUPER_PASSWORD`, `ADJUTANT_DB_PASSWORD`, `DASHBOARD_DB_PASSWORD`,
`MINIFLUX_DB_PASSWORD`, `MARKETS_DB_PASSWORD`, `WELLTHREAD_DB_PASSWORD`,
`AUTHENTICATOR_PASSWORD`, `AUTH_ADMIN_PASSWORD`), `BESZEL_API_PASSWORD`,
the shared bearer tokens (`ADJUTANT_API_TOKEN`/`API_BEARER_TOKEN`,
`ARTICLE_INGEST_TOKEN`, `MARKETS_API_TOKEN`), and `SUPABASE_JWT_SECRET`
(plus its derived `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY`, which
required a `wellthread-web` rebuild since the anon key is baked into the
client bundle at build time) were rotated on live CT110 and verified —
every service reconnected clean, and the new anon JWT was confirmed accepted
by PostgREST before/after cutover. New values were generated and installed
entirely server-side and never printed to any transcript.

**Deliberately not rotated:**

- `LITELLM_API_KEY` — the LiteLLM master key is shared with OpenClaw, a
  system outside this workspace with no config reachable from here.
  Rotating it would 401 every OpenClaw call until its config is updated in
  lockstep. Do this the next time an OpenClaw-side change is already
  planned, so both sides move together.
- `MINIFLUX_ADMIN_PASSWORD`, `MINIFLUX_TOKEN`, `LINKDING_PASSWORD` —
  single-consumer human-login credentials (not producer/consumer pairs
  needing coordination). Rotate directly in each app's UI: Miniflux
  Settings → change password, then Settings → API keys → regenerate →
  update `.env`; Linkding via its own login settings.

**Still open:** external credential rotation (Anthropic, Cloudflare) —
tracked separately, not done from this environment. File permissions were
already contained at `0600` prior to this rotation.

## 2. Establish real disaster recovery

PostgreSQL backup and disposable restore testing are live, but the dumps share
CT110's physical disk. When USB or network storage is available:

1. replicate completed dump/checksum pairs off-host;
2. configure Proxmox `vzdump` to that external target for full-LXC recovery;
3. include stateful non-Postgres volumes; and
4. perform and document an external restore test.

Until that succeeds, same-host dumps are recovery staging only.

## 3. Normalize the CT110 deployment checkout

`/opt/homelab` has a local commit and uncommitted bring-up changes, including
runtime configuration that must not be lost. It also still uses an HTTPS Git
remote. Reconcile it deliberately:

1. inventory the local commit and every changed/untracked path without printing
   secret contents;
2. preserve `.env` and `.env.adjutant` outside Git with root-only permissions;
3. ensure every durable non-secret operational change exists on GitHub;
4. create a clean SSH-backed deployment checkout or carefully converge the
   existing one; and
5. run the full Compose parse and health checks before retiring the old copy.

Do not solve this with `reset --hard`, `checkout --`, or deletion of the live
directory.

## 4. Add the first approval-gated infrastructure action

Create a least-privilege Proxmox API token with the `PVEAuditor` role and add a
read-only Adjutant tool first. When the first mutation is introduced—likely a
targeted container restart—implement runner resumption after
`POST /approvals/{id}/resolve`. The API records decisions today but does not
resume blocked work, and no registered tool currently uses the `APPROVAL` tier.

## 5. Finish content automation

- Seed a non-markets/non-fantasy morning briefing schedule using Miniflux.
- Wire OpenClaw article publishing to the dashboard's real
  `POST /api/ingest/articles` route.
- Confirm Miniflux's first login/API token if it has not already been completed.

## 6. Complete Fantasy Edge identity reconciliation

Fantasy Edge's `/props` data is live and used today, but ranking endpoints
remain empty until historical and live-synced `Team` rows share identity. This
work belongs in the Fantasy Edge repository and must be verified there before
the dashboard or Adjutant treats ranking output as populated.

## Future hardware

- HP EliteDesk nodes: validate and execute [K8S-CLUSTER-GUIDE.md](K8S-CLUSTER-GUIDE.md).
- Intel node: move Jellyfin there for Quick Sync.
- GPU node: change only LiteLLM routing after a canary period.
