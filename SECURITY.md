# Security Model

Last verified 2026-08-05 against Compose and live CT110. This document records
the controls that exist and the risks intentionally accepted; it is not a claim
that containers are a security boundary equivalent to separate VMs.

## Boundaries and assets

The sensitive assets are provider API keys, service bearer tokens, database
credentials/data, Cloudflare tunnel credentials, and control of the nested
Docker daemon. CT110 is an unprivileged Proxmox LXC, but Docker runs with
nesting enabled inside it. A Docker-daemon compromise therefore owns the
application stack and CT110 data even though the outer LXC still limits direct
access to the Proxmox host.

Secrets live in root-owned `.env` and `.env.adjutant` files and are injected at
container creation. GitHub `main` ignores both. CT110's historical local-only
bring-up commit does contain `.env`; it has not been pushed, but checkout
normalization remains a priority in `NEXT-STEPS.md`. Both live secret files must
be mode `0600`.

During the 2026-08-05 hardening session, a local Compose validation command
printed resolved environment values into the private task transcript. The
files and their backups were immediately restricted to `0600`, and the
incident created no new commit or push containing secrets. All external and
internal credentials still require coordinated rotation; that
incident-response work is priority 1 in `NEXT-STEPS.md`.

## LiteLLM

LiteLLM is the sole gateway to local and cloud models. Model/API requests
require `LITELLM_MASTER_KEY`; the local liveness endpoint is deliberately
unauthenticated. Provider credentials are injected only into this container.
The configuration bind mount is read-only.

Compose additionally enforces:

- image-provided UID/GID `65532:65532` (`nonroot`);
- read-only root filesystem with only a 64 MiB, `noexec`, `nosuid` `/tmp`;
- all Linux capabilities dropped and `no-new-privileges` enabled;
- a 256-process ceiling and 1536 MiB memory ceiling;
- an unauthenticated local liveness check; and
- explicit IPv4-only publishing on TCP 4000, preventing an accidental future
  IPv6 listener.

TCP 4000 remains reachable from the trusted private LAN because OpenClaw and
other LXCs consume it. There is no Cloudflare Tunnel hostname or router port
forward for LiteLLM. Proxmox currently has no CT-specific firewall rules, so
the master key—not source-IP filtering—is the request authorization boundary.
HTTP on the trusted private LAN is an accepted residual risk: the bearer key
is not transport-encrypted there. If untrusted devices join that network,
place LiteLLM behind a TLS/mTLS or VPN-only proxy before allowing them access.

## Beszel Docker socket

`beszel-agent` mounts `/var/run/docker.sock` with `:ro`. That flag prevents the
container from replacing the socket path; it **does not make the Docker API
read-only**. Any process that can speak to the socket has root-equivalent
control of the Docker daemon: it can create privileged containers, mount CT110
paths, inspect secret-bearing container configuration, stop workloads, and
exfiltrate data.

This is an explicit accepted trust decision because per-container monitoring
is a core Beszel function. The pinned Beszel image is therefore treated as
root-equivalent third-party code. Surrounding defense-in-depth controls are a
read-only root filesystem, 16 MiB hardened `/tmp`, all capabilities dropped,
`no-new-privileges`, a 128-process ceiling, SSH public-key authentication from
the hub, and no additional host-path mounts. These controls reduce unrelated
kernel/filesystem attack surface but cannot contain a process that successfully
uses the Docker socket.

A Docker socket proxy is a future option only after Beszel's exact endpoint set
is measured and tested; an incorrectly broad proxy creates the same trust with
extra complexity, while an overly narrow one silently breaks monitoring.

## Verification

`tests/test-security-contract.sh` prevents removal of the declared Compose
controls or documentation of the two accepted residual risks. Before the live
change, disposable containers verified that:

- LiteLLM starts, passes `/health/liveliness`, and returns the authenticated
  model catalog under the proposed controls; and
- Beszel agent starts, discovers Docker/network metrics, and opens its SSH
  listener under the proposed controls.

Production rollout must recreate only `litellm` and `beszel-agent`, verify
their health/logs, confirm an authenticated LiteLLM request from an existing
consumer, and confirm Beszel continues receiving CT110 metrics.
