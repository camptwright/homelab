# Postgres Backup Staging Design

## Purpose

Protect the homelab's shared Postgres cluster against accidental deletion,
bad migrations, and other logical failures while no off-host backup target is
available. These backups are recovery staging on CT110, not disaster recovery:
they do not survive loss of the Proxmox host or its storage.

## Scope

This change provides:

- nightly compressed logical backups of the complete Postgres cluster;
- atomic publication of validated backup files;
- SHA-256 checksums;
- fourteen-day local retention;
- a disposable restore test; and
- a systemd service and timer installed on CT110.

It does not configure Proxmox `vzdump`, copy data off-host, back up non-Postgres
volumes, or send failure notifications. Those capabilities wait for an external
USB or network storage target.

## Repository Components

`scripts/backup-postgres.sh` creates a cluster-wide `pg_dumpall` from the
Compose-managed `postgres` service. It writes to a restrictive temporary file
under `/opt/backups/postgres`, validates the gzip stream, moves it atomically to
its UTC-timestamped final name, writes a checksum, and removes completed backup/checksum
pairs older than fourteen days. A non-blocking `flock` prevents overlapping
runs. Any failed command exits non-zero and leaves no completed-looking dump.
Cluster dumps include role password hashes and are treated as secrets: the
backup directory is mode 0700 and dump/checksum files are readable only by root.

`scripts/restore-test-postgres.sh` accepts a completed dump, verifies its
checksum and gzip stream, starts a temporary `pgvector/pgvector:pg16` container
with ephemeral database storage, restores the cluster dump, and checks that the
expected application databases exist. Its cleanup trap removes the temporary
container on success or failure. It never connects the disposable database to
the production Postgres volume.

`systemd/homelab-postgres-backup.service` runs the backup script as a oneshot
root service. `systemd/homelab-postgres-backup.timer` runs it nightly at 02:15
in CT110's local timezone and uses a persistent timer so a missed run occurs
after the LXC next starts.

## Data and Failure Flow

1. The timer starts the oneshot service.
2. The backup script acquires its lock and creates a mode-0600 temporary file.
3. `docker compose exec -T postgres pg_dumpall -U postgres` streams into gzip.
4. The script verifies the gzip stream before publishing it.
5. The temporary file is atomically renamed and a SHA-256 checksum is written.
6. Backup/checksum pairs older than fourteen days are removed.
7. systemd records success or the failing command's non-zero exit status.

Interrupted or failed runs may leave a temporary file, but never a final
`.sql.gz` file. The next run removes stale temporary files before starting.

## Installation

The repository remains the source of truth. Installation copies the scripts to
`/opt/homelab/scripts`, copies the units to `/etc/systemd/system`, reloads
systemd, enables the timer, and runs the service once immediately. Secrets are
not copied from CT110 and do not appear in scripts, logs, or repository files.

## Verification

Installation is complete only when all of these pass:

1. Shell syntax checks for both scripts.
2. The systemd units verify successfully.
3. The first service run creates a non-empty gzip file and matching checksum.
4. The checksum and gzip integrity checks pass.
5. The disposable restore test imports the newest dump and confirms these
   databases: `adjutant`, `dashboard`, `markets`, `miniflux`, and `wellthread`.
6. The production Postgres container remains healthy after the test.
7. The timer is enabled and has a future next-run timestamp.

## Future Off-Host Extension

When external storage becomes available, add a separate replication step that
copies only completed dump/checksum pairs to that target. Configure Proxmox
`vzdump` on the external target for full-LXC recovery and test a restore. Do not
relabel the local staging directory as a disaster-recovery backup.
