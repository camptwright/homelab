# Postgres Backup Staging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install and verify nightly, locally staged Postgres cluster backups on CT110 with integrity checks, retention, and a disposable restore test.

**Architecture:** Two focused Bash programs own backup creation and restore verification. A systemd oneshot service and persistent timer schedule backup creation; repository tests use a fake Docker executable, while final verification runs against the live Compose stack and an isolated ephemeral Postgres container.

**Tech Stack:** Bash 5, Docker Compose, PostgreSQL 16 tools, gzip, sha256sum, flock, systemd.

## Global Constraints

- Local backups are recovery staging and must never be described as off-host disaster recovery.
- Store completed artifacts under `/opt/backups/postgres` with directory mode `0700` and file mode `0600`.
- Use UTC timestamps in filenames and retain completed backups for fourteen days.
- Never publish a completed filename until the gzip stream passes validation.
- Never mount or connect the production Postgres data volume during restore testing.
- Do not copy secrets from CT110 or print dump contents.

---

### Task 1: Atomic cluster backup program

**Files:**
- Create: `scripts/backup-postgres.sh`
- Create: `tests/test-backup-postgres.sh`

**Interfaces:**
- Consumes: `docker compose exec -T postgres pg_dumpall -U postgres` from `/opt/homelab`.
- Produces: `pg-YYYYmmddTHHMMSSZ.sql.gz` and matching `.sha256` files in `BACKUP_DIR`.

- [ ] **Step 1: Write the failing backup test**

Create a temporary fake `docker` that emits a minimal valid SQL stream, run the not-yet-created script with `BACKUP_DIR`, `COMPOSE_DIR`, and `LOCK_FILE` redirected into the temporary directory, and assert:

```bash
mapfile -t dumps < <(find "$BACKUP_DIR" -name 'pg-*.sql.gz')
[[ ${#dumps[@]} -eq 1 ]]
gzip -t "${dumps[0]}"
(cd "$BACKUP_DIR" && sha256sum -c "$(basename "${dumps[0]}").sha256")
[[ $(stat -c '%a' "$BACKUP_DIR") == 700 ]]
[[ $(stat -c '%a' "${dumps[0]}") == 600 ]]
```

- [ ] **Step 2: Confirm the test fails**

Run: `bash tests/test-backup-postgres.sh`

Expected: non-zero because `scripts/backup-postgres.sh` does not exist.

- [ ] **Step 3: Implement the backup program**

The script must use `set -Eeuo pipefail`, `umask 077`, configurable `BACKUP_DIR`, `COMPOSE_DIR`, `LOCK_FILE`, and `RETENTION_DAYS`, plus this sequence:

```bash
mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 75
find "$BACKUP_DIR" -maxdepth 1 -type f -name '.pg-*.tmp' -mtime +1 -delete
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
temporary="$BACKUP_DIR/.pg-$timestamp.sql.gz.tmp"
completed="$BACKUP_DIR/pg-$timestamp.sql.gz"
trap 'rm -f -- "$temporary"' EXIT
cd "$COMPOSE_DIR"
docker compose exec -T postgres pg_dumpall -U postgres | gzip -9 >"$temporary"
test -s "$temporary"
gzip -t "$temporary"
mv "$temporary" "$completed"
chmod 0600 "$completed"
(cd "$BACKUP_DIR" && sha256sum "$(basename "$completed")" >"$(basename "$completed").sha256")
chmod 0600 "$completed.sha256"
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'pg-*.sql.gz' -o -name 'pg-*.sql.gz.sha256' \) -mtime "+$RETENTION_DAYS" -delete
```

Print only the completed path and byte count.

- [ ] **Step 4: Run the backup test and syntax check**

Run:

```bash
bash -n scripts/backup-postgres.sh tests/test-backup-postgres.sh
bash tests/test-backup-postgres.sh
```

Expected: both commands exit zero.

- [ ] **Step 5: Commit Task 1**

```bash
git add scripts/backup-postgres.sh tests/test-backup-postgres.sh
git commit -m "feat: add atomic Postgres backup script"
```

### Task 2: Disposable restore verification

**Files:**
- Create: `scripts/restore-test-postgres.sh`
- Create: `tests/test-restore-postgres.sh`

**Interfaces:**
- Consumes: one completed dump path from Task 1, or the newest dump in `BACKUP_DIR` when no argument is supplied.
- Produces: exit zero only after checksum, gzip, restore, and expected-database checks pass.

- [ ] **Step 1: Write the failing restore-flow test**

Create a temporary valid gzip/checksum pair and a fake `docker` that records invocations. The fake must return success for `run`, `exec ... pg_isready`, streamed `exec -i ... psql`, and `rm -f`; for the database query it must print:

```text
adjutant
dashboard
markets
miniflux
wellthread
```

Assert that the script exits zero and that the invocation log includes `--tmpfs`, `psql -v ON_ERROR_STOP=1`, and `rm -f`.

- [ ] **Step 2: Confirm the restore test fails**

Run: `bash tests/test-restore-postgres.sh`

Expected: non-zero because `scripts/restore-test-postgres.sh` does not exist.

- [ ] **Step 3: Implement the restore-test program**

The script must:

1. Resolve the supplied dump or newest `pg-*.sql.gz` under `BACKUP_DIR`.
2. Require and verify `<dump>.sha256` from inside its directory.
3. Run `gzip -t`.
4. Start `pgvector/pgvector:pg16` with a unique name, `POSTGRES_HOST_AUTH_METHOD=trust`, and `--tmpfs /var/lib/postgresql/data`, using the image's normal `postgres` bootstrap superuser.
5. Register an EXIT trap that runs `docker rm -f` for the disposable container.
6. Poll `pg_isready -U postgres` for at most 30 seconds.
7. Stream `gzip -cd "$dump"` through `sed '/^CREATE ROLE postgres;$/d'` and into `docker exec -i <container> psql -v ON_ERROR_STOP=1 -U postgres`. This removes only the role creation that conflicts with the image's bootstrap superuser; the stored dump remains unchanged and its following `ALTER ROLE postgres ...` statement still restores the production attributes.
8. Query `pg_database` and fail unless all five expected application databases exist.
9. Print the verified dump path without printing SQL or role data.

- [ ] **Step 4: Run restore tests and syntax checks**

Run:

```bash
bash -n scripts/restore-test-postgres.sh tests/test-restore-postgres.sh
bash tests/test-restore-postgres.sh
```

Expected: both commands exit zero and the fake invocation log confirms cleanup.

- [ ] **Step 5: Commit Task 2**

```bash
git add scripts/restore-test-postgres.sh tests/test-restore-postgres.sh
git commit -m "feat: add disposable Postgres restore test"
```

### Task 3: Scheduling, documentation, and live installation

**Files:**
- Create: `systemd/homelab-postgres-backup.service`
- Create: `systemd/homelab-postgres-backup.timer`
- Modify: `SETUP.md` backup section

**Interfaces:**
- Consumes: `/opt/homelab/scripts/backup-postgres.sh` from Task 1.
- Produces: `homelab-postgres-backup.timer`, enabled on CT110 with a future trigger.

- [ ] **Step 1: Add the systemd units**

Service contract:

```ini
[Unit]
Description=Homelab Postgres cluster backup
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/homelab
ExecStart=/opt/homelab/scripts/backup-postgres.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

Timer contract:

```ini
[Unit]
Description=Nightly homelab Postgres cluster backup

[Timer]
OnCalendar=*-*-* 02:15:00
Persistent=true
RandomizedDelaySec=10m
Unit=homelab-postgres-backup.service

[Install]
WantedBy=timers.target
```

- [ ] **Step 2: Replace the aspirational backup note in `SETUP.md`**

Document the exact installed service/timer names, artifact location, manual backup command, restore-test command, fourteen-day retention, `journalctl` inspection command, and the same-host limitation. Preserve the future requirement for external `vzdump` and off-host replication.

- [ ] **Step 3: Verify repository artifacts**

Run:

```bash
bash -n scripts/*.sh tests/test-*.sh
bash tests/test-backup-postgres.sh
bash tests/test-restore-postgres.sh
systemd-analyze verify systemd/homelab-postgres-backup.service systemd/homelab-postgres-backup.timer
git diff --check
```

On macOS, `systemd-analyze` is expected to be unavailable; run that command on CT110 before installation instead.

- [ ] **Step 4: Commit Task 3 and push the repository**

```bash
git add systemd SETUP.md
git commit -m "ops: schedule nightly Postgres backups"
git push origin main
```

- [ ] **Step 5: Deploy only the reviewed backup artifacts**

Copy both scripts and both units through the Proxmox host, install scripts mode `0750` and units mode `0644`, then run:

```bash
systemd-analyze verify /etc/systemd/system/homelab-postgres-backup.service /etc/systemd/system/homelab-postgres-backup.timer
systemctl daemon-reload
systemctl enable --now homelab-postgres-backup.timer
systemctl start homelab-postgres-backup.service
```

- [ ] **Step 6: Verify the first live backup**

Run root-only checksum and gzip checks against the newest artifact. Confirm the backup service exited successfully and the timer reports both `enabled` and a future `NEXT` timestamp.

- [ ] **Step 7: Run the disposable live restore test**

Run `/opt/homelab/scripts/restore-test-postgres.sh` against the newest dump. Confirm all five expected databases are reported, the disposable container no longer exists afterward, and `homelab-postgres-1` remains healthy.

- [ ] **Step 8: Record the remaining off-host dependency**

Report that full-LXC `vzdump`, non-Postgres volume coverage, and off-host replication remain blocked until USB or network storage is available. Do not mark disaster recovery complete.
