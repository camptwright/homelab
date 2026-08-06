# Next Steps

Open work only, ordered by operational value. Last verified 2026-08-05.
Completed architecture and service state belong in [README.md](README.md);
durable failure modes belong in [CLAUDE.md](CLAUDE.md).

## 1. Rotate credentials exposed during local hardening

On 2026-08-05, a production Compose validation command printed resolved
environment values into a private Codex task transcript. No values were
committed or pushed, but treat every credential in `.env` and `.env.adjutant`
as exposed to that transcript.

Rotate external credentials first (Anthropic and Cloudflare), then coordinate
internal database passwords, JWT secrets, and shared service bearer tokens so
every producer/consumer is updated together. Recreate only affected services,
verify health after each group, and invalidate old credentials where the
provider supports it. Never print the resolved Compose model while doing this.

File permissions have already been contained at `0600`; rotation remains open.

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
