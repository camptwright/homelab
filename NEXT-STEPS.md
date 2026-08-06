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

## 3. Normalize the CT110 deployment checkout — done (2026-08-06)

`/opt/homelab` is now a clean SSH-based clone (`git@github.com-homelab:...`,
a dedicated read-only deploy key registered on the repo — see `~/.ssh/config`
on CT110) tracking `main` with a clean `git status`. A file-by-file diff
against the old checkout found the drift was entirely in docs/tests/planning
files, never in anything functional — `docker-compose.yml`, `postgres-init.sql`,
`litellm-config.yaml`, `SETUP.md`, and `scripts/*` already matched exactly,
confirming prior sessions' direct file pushes had kept the runtime state in
sync even though git's own HEAD was stuck on a July 31 local commit. `.env`
and `.env.adjutant` were copied across untouched (root-only `0600`), and
`docker compose config` was confirmed to resolve identically before and
after the swap (the only diff pre-swap was the absolute bind-mount path,
which self-corrected once the clean checkout landed at `/opt/homelab`). The
swap was a directory rename only — zero containers restarted, confirmed by
unchanged uptimes across all 18 services.

**One finding needs a decision:** the old checkout (preserved, not deleted,
at `/opt/homelab.pre-reconcile-<timestamp>`) has a local-only git commit
(`bf96a62`, "litellm update", 2026-07-31) that committed a real `.env` into
its `.git` history. That commit was **never pushed** — `homelab` is a public
GitHub repo, but `bf96a62` is not reachable from `origin/main`, confirmed via
`git merge-base --is-ancestor`. So this was never a public leak; it's local,
root-only exposure on a single-user host, and every credential it could have
contained was rotated in item 1 above (except the external provider keys,
which are the user's separate responsibility). Delete
`/opt/homelab.pre-reconcile-<timestamp>/.git` (or the whole directory) once
you're comfortable it's no longer needed as a rollback reference — it also
still holds several `.bak` files from earlier sessions if any of those are
ever wanted.

## 4. Add the first approval-gated infrastructure action — done (2026-08-06)

`proxmox_status` (read-only) and `restart_container` (the first real
`APPROVAL`-tier tool) both live on Adjutant's infra agent, authenticated via
a dedicated `adjutant@pve` Proxmox user with exactly two ACL grants
(`PVEAuditor` read-only + a custom `VM.PowerMgmt`-only role — nothing
broader) and TLS pinned to the node's own CA. Runner resumption after
`POST /approvals/{id}/resolve` is built and verified live: a real restart
request for a real running container blocked on a real `Approval` row,
was denied through the real API, and the container's Proxmox-reported
uptime never reset — proof the real handler never ran, and proof the
task still reached a real conclusion instead of sitting at `pending`
forever. See `adjutant/NEXT-STEPS.md` for the full verification detail.

## 5. Finish content automation — mostly done (2026-08-06)

- **Done:** a `briefing` sub-agent reads unread Miniflux articles and posts
  a daily 07:00 `America/Chicago` morning briefing (`source=briefing`).
  Verified live: real Miniflux entries pulled, a real article posted and
  confirmed present in the dashboard's Postgres.
- **Still open:** wiring OpenClaw's article publishing to
  `POST /api/ingest/articles` needs no code — the route, auth, and
  contract are already proven by the fantasy/markets/briefing agents —
  it's purely configuring the external OpenClaw system (URL +
  `ARTICLE_INGEST_TOKEN`), which lives outside this workspace.
- Confirm Miniflux's first login/API token if it has not already been
  completed (it has — the briefing agent's live verification used the
  real configured token successfully).

## 6. Complete Fantasy Edge identity reconciliation — done (2026-08-06)

Fixed and verified live against real Postgres on CT100: `resolve_team()`
now backs both `seed_historical.py` and `GameSyncAgent`, crosswalking
NFL/MLB/NHL's historical-loader identifiers to ESPN's canonical
name/espn_id (fetched live, not from memory). 560/561 seeded NFL games
now resolve both `home_team_id`/`away_team_id` (the one holdout predates
the current team-abbreviation convention, a documented, narrow gap, not
a regression). NCAAF's crosswalk remains unbuilt — its ~130-school
roster is too large and too volatile to hand-type without live
verification; see fantasy-edge's own CLAUDE.md for the full detail,
including two real bugs found and fixed along the way (an NHL loader
field that doesn't exist in the real API schema, and a YAML `NO` key
that silently parsed as the boolean `False`). Populated `/rankings/*`
output additionally depends on `ValueAgent` actually running against the
now-resolved teams — not independently re-verified beyond confirming the
resolution pipeline itself is clean end-to-end.

## Future hardware

- HP EliteDesk nodes: validate and execute [K8S-CLUSTER-GUIDE.md](K8S-CLUSTER-GUIDE.md).
- Intel node: move Jellyfin there for Quick Sync.
- GPU node: change only LiteLLM routing after a canary period.
