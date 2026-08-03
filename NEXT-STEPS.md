# NEXT-STEPS.md

Living status note. Last updated **2026-08-03**, mid-way through building
a new "markets" stack (marketdesk service + dashboard stocks tile +
Adjutant markets sub-agent) — written early because a session usage limit
was imminent. See `homelab-dashboard/NEXT-STEPS.md` Part 6 and
`marketdesk/NEXT-STEPS.md` for the full detail; this is the homelab-repo-
specific slice.

## Done this session (see CLAUDE.md for the full lesson writeups)

- Fixed `beszel-agent` crash loop (wrong key format), linkding login
  (stale superuser password vs a persistent volume), the dashboard's
  never-migrated database (zero tables existed), and a missing `DOMAIN`
  env var that broke every quick-link.
- `dashboard`'s System tile now does real Beszel + Uptime Kuma reads
  (was a hardcoded placeholder before) — needed `BESZEL_API_EMAIL`/
  `BESZEL_API_PASSWORD` (new dedicated service account) and
  `UPTIME_KUMA_STATUS_SLUG` added to `.env` and `docker-compose.yml`.
  Both already live on CT 110.
- `markets` Postgres user + database created live on CT 110's shared
  Postgres (one-time `CREATE USER`/`CREATE DATABASE`/`ALTER USER`),
  `MARKETS_DB_PASSWORD` generated and in `.env`. **This has NOT been added
  to `postgres-init.sql` yet** — a fresh install of this stack would not
  get the `markets` role/db automatically; needs the same treatment as
  `wellthread`'s roles (see CLAUDE.md's `postgres-init.sql` lesson).

## Not done yet — needed before the markets stack is real

1. **`docker-compose.yml` does not have a `marketdesk` service block.**
   The exact block (env vars, `mem_limit: 384m`, `depends_on: postgres
   healthy`) is specified in the original request that started this work
   — add it under `profiles: [apps]` once the marketdesk image is
   actually buildable and pushed to GHCR (see `marketdesk/NEXT-STEPS.md`
   for what's still missing there first).
2. **`MARKETS_API_TOKEN` does not exist in `.env` yet** (only
   `MARKETS_DB_PASSWORD` does). Generate with `openssl rand -hex 32` and
   add it before wiring the compose block.
3. **`postgres-init.sql`** needs the `markets` user/database/grants added
   for fresh installs, mirroring the live commands already run.
4. **`env.example`** needs `MARKETS_DB_PASSWORD`, `MARKETS_API_TOKEN`,
   `FINNHUB_API_KEY`, `ALPHAVANTAGE_API_KEY` documented (all currently
   absent from the template).

## A hard blocker surfaced this session, not yet resolved

**Adjutant does not exist as a codebase anywhere** — confirmed absent both
locally (`~/code/`) and on GitHub under every name I could plausibly guess
(`adjutant`, `adjutant-agent`, `camp-adjutant`, `homelab-adjutant`, all
404). Homelab's own `CLAUDE.md` describes it in the "Related Repos"
section as if it's an existing project with `PROMPTS.md` 1-9 already
written, but the roadmap section of the same file says "Adjutant Phase 1"
is still a future step — it's aspirational documentation, not a
description of something that exists. Before any further work references
Adjutant as if it's a real codebase to extend, this needs to be
reconciled: either point me at the actual location, or confirm it needs
to be built from scratch (a large, separate undertaking — see the
original markets-sub-agent request for the shape it would need: shared
runner, SYSTEM.md convention, tool tiers, an orchestrator, a schedules
table).
