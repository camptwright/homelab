# NEXT-STEPS.md

Living status note. Last updated **2026-08-04**. See `CLAUDE.md`'s
"Current State / Roadmap" section for the authoritative day-to-day summary
and the operational-lessons list for failure modes already hit and fixed.
This file is the shorter "what's actually left" slice.

## Done (markets + fantasy stack, end to end)

- `marketdesk` built, tested, and deployed live on CT110 (profile `apps`,
  `mem_limit: 384m`, own `markets` Postgres db/user - already in
  `postgres-init.sql` and `env.example`). Consumed for real by both the
  dashboard's Stocks tile and Adjutant's markets agent.
- `adjutant` built, tested, and deployed live on CT110 (profile
  `adjutant`). Three agents: `infra`, `markets`, and `fantasy`. Two
  markets schedules plus a `fantasy_recap` schedule are seeded and
  running. All three verified end-to-end against real infra with real
  published articles landing in the dashboard's Postgres.
- Dashboard's Stocks tile (`/stocks`) and Fantasy tile (`/fantasy`) are
  both live and consuming their real backing APIs, not placeholders.
- The fantasy agent's article-publishing bug (empty-endpoint tool
  selection, then the model skipping `post_article` entirely) is fixed
  with a mechanical runner-level nudge - see `adjutant/NEXT-STEPS.md` for
  the full investigation.

## Not done yet

1. **GHCR package visibility is unconfirmed for `dashboard`, `marketdesk`,
   and `adjutant` alike.** All three were deployed by building the image
   directly from source on the LXC, because `docker pull
   ghcr.io/camptwright/<image>:latest` returned `unauthorized` and fixing
   it needed a `gh auth refresh` that couldn't complete a browser
   confirmation in a non-interactive session. Before trusting a plain
   `docker compose pull && up -d` on any future redeploy of these three
   services, make each GHCR package public via the GitHub UI (Settings ->
   Package -> Change visibility) or complete the interactive `gh auth
   refresh` with `read:packages` scope, then verify the pull actually
   succeeds.
2. **No Proxmox integration for the infra agent.** `PROXMOX_TOKEN_ID`/
   `PROXMOX_TOKEN_SECRET` are documented in `.env.adjutant`'s contract but
   nothing consumes them yet. Needs a hand-made PVEAuditor API token.
3. **No AUTO-resumption of an `APPROVAL`-tier task.** `POST
   /approvals/{id}/resolve` records the human decision but doesn't
   re-enter the paused runner loop - unexercised today since nothing
   registered is `APPROVAL`-tier. Build this alongside the first tool
   that actually needs approval (likely "restart a container" once the
   Proxmox integration lands).
4. **Fantasy Edge's team-identity reconciliation (its own constraint #24)
   is filed but not started.** `/rankings/{sport}` stays empty until
   historical and live-synced `Team` rows share identity. Doesn't block
   the current fantasy agent (it reads `/props`, not `/rankings`) but
   will need doing before Fantasy Edge's own ranking-based output is
   trustworthy.
5. **Morning briefing schedule for non-markets/non-fantasy sources** and
   OpenClaw ingest wiring are still future work (SETUP.md Part B3/B4).
