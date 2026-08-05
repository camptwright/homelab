# Homelab Kubernetes Cluster + Adjutant Deployment Guide

> **Future design, not an executed runbook.** No HP-node cluster exists yet.
> Revalidate Proxmox, Ubuntu, k3s, kube-vip, MetalLB, CloudNativePG, and image
> versions against current upstream documentation before running these steps.
> The live CT110 Compose stack remains authoritative until a separately tested
> migration and rollback plan is approved.

Proxmox cluster across the KAMRUI Pinova P1 and 2-3 HP EliteDesk 800 G5 Minis, k3s Kubernetes in VMs on the HP nodes, and the Adjutant agent stack deployed on top.

Written for 3 HP nodes (the ideal: HA control plane). Every place the 2-node variant differs is marked **[2-HP variant]**.

---

## Part 0 - Topology and IP Plan

| Machine | Hostname | Role | IP |
|---|---|---|---|
| KAMRUI Pinova P1 (R2544, 16GB) | `pve-svc` | Proxmox quorum + utility LXCs (DNS, backups, LiteLLM until GPU node exists) | 192.168.1.10 |
| HP EliteDesk 1 (i5-9500T, 32GB) | `pve-hp1` | Proxmox, hosts k3s VM 1 | 192.168.1.11 |
| HP EliteDesk 2 | `pve-hp2` | Proxmox, hosts k3s VM 2 | 192.168.1.12 |
| HP EliteDesk 3 | `pve-hp3` | Proxmox, hosts k3s VM 3 | 192.168.1.13 |
| k3s VM 1 | `k3s-1` | k3s server (etcd) | 192.168.1.21 |
| k3s VM 2 | `k3s-2` | k3s server (etcd) | 192.168.1.22 |
| k3s VM 3 | `k3s-3` | k3s server (etcd) | 192.168.1.23 |
| kube-vip virtual IP | - | floating control-plane endpoint | 192.168.1.20 |
| MetalLB pool | - | LoadBalancer service IPs | 192.168.1.240-192.168.1.250 |

Adjust the subnet to whatever your Fort Worth LAN actually uses; keep the pattern (hosts low, VMs in the 20s, LB pool in a reserved high range). Reserve all of these in your router's DHCP settings so nothing collides.

**Why this shape:**
- Proxmox clusters need an odd-ish quorum. KAMRUI + 3 HPs = 4 votes, quorum 3, tolerates 1 node down. KAMRUI + 2 HPs = 3 votes, also tolerates 1 down. Both fine, no QDevice needed.
- The R2544 is 2 cores / 16GB; it would be the weakest K8s node by far and drag scheduling. As a quorum + services node it is perfectly employed.
- k3s runs in VMs, not LXCs. Kubernetes inside LXC requires privileged containers and AppArmor/cgroup surgery that breaks on upgrades. VMs cost a little overhead and save you hours.

**[2-HP variant]** k3s-1 is the single server (control plane + etcd), k3s-2 is an agent (worker). No kube-vip, no HA; the API endpoint is just 192.168.1.21. Everything else is identical.

**Shopping note:** the G5 Minis usually ship with 256GB NVMe. Longhorn and Postgres will want room; a 500GB-1TB NVMe per HP (~$40-60) is the single best upgrade before you start. The G5 also has a 2.5" SATA bay if you want a second disk dedicated to Longhorn later.

---

## Part 0.5 - Apartment Networking (REQUIRED in this setup)

The apartment network (10.24.51.0/24, no router access) cannot host the cluster directly:

- No DHCP reservations means the apartment DHCP server will eventually assign one of your "static" IPs to another tenant's device.
- Managed apartment networks frequently enable client isolation, which blocks device-to-device traffic. Corosync, etcd, and everything else in this guide requires nodes to reach each other.
- MetalLB (L2 mode) and kube-vip claim IPs via ARP announcement. Managed networks often filter unknown MACs and gratuitous ARP, breaking both silently.

**Solution: your own router in front of everything.** Router WAN plugs into the apartment jack (or joins apartment WiFi in WiFi-as-WAN mode; GL.iNet routers do this best). All cluster nodes plug into the router's LAN ports (add a small unmanaged gigabit switch if you run out). The apartment network sees one device: your router.

Rules for the private LAN:

1. **Do not reuse 10.24.51.0/24 internally.** Overlapping the upstream subnet makes routing ambiguous. This guide's 192.168.1.0/24 plan now applies verbatim behind your router; if you prefer 10.x, use something distinctive like 10.89.0.0/24 and substitute throughout.
2. Set DHCP reservations on **your** router for every entry in the Part 0 table, even the statically configured ones. Belt and suspenders.
3. Node-to-node traffic (corosync, etcd, pod networking, Longhorn replication) never leaves your switch/router, so cluster performance is identical to a normal home network even if the apartment uplink is WiFi.

**Consequences of double NAT (apartment NAT + your NAT):**

- No inbound port forwarding from the internet. Already your reality; the Cloudflare Tunnel pattern from the wedding platform continues to work unchanged for anything public.
- For private remote access, run **Tailscale as a subnet router** in an LXC on pve-svc: `tailscale up --advertise-routes=192.168.1.0/24`, approve the route in the admin console, and enable IP forwarding in the LXC. Then kubectl, the Proxmox web UIs, and SSH all work from your laptop or phone anywhere, with zero exposed ports. This also fixes the day-to-day annoyance that your laptop on apartment WiFi is outside your private LAN: install Tailscale on the laptop and you are always "inside."
- Point your workstation kubeconfig at the VIP as usual; over Tailscale it resolves through the advertised route with no changes.

**MAC registration bonus:** if the apartment ISP requires registering devices by MAC address or has a captive portal, you now register exactly one device (the router) instead of six.

---

## Part 1 - BIOS Prep (each HP EliteDesk)

Power on, mash F10:

1. **Advanced > System Options**: enable VT-x and VT-d.
2. **Advanced > Power Management (or Built-In Device Options)**: set **After Power Loss = Power On**. Mini PC clusters die to power blips; this brings them back without you touching them.
3. Disable Secure Boot (Proxmox installs fine without fighting it).
4. Optional: enable Wake-on-LAN.
5. Set boot order to USB first for install.

KAMRUI: enable SVM (AMD virtualization) in its BIOS, same power-on-after-loss setting if it exists.

---

## Part 2 - Install Proxmox on Every Node

1. Download the Proxmox VE 8.x ISO, write it to USB (Rufus in DD mode, or `dd`).
2. Install on each machine. During install:
   - Target disk: the NVMe. Filesystem: ext4 with LVM-thin (default) is fine at this scale. Skip ZFS on these boxes; ZFS wants RAM you would rather give to VMs.
   - Set the static IP, hostname (FQDN style, e.g. `pve-hp1.lan`), gateway, and DNS per the table.
3. First boot, on **every** node, fix repos and update (no subscription):

```bash
# disable enterprise repos
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/pve-enterprise.list
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/ceph.list 2>/dev/null
# add no-subscription repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
apt update && apt full-upgrade -y
```

4. Verify time sync on every node (`timedatectl`); corosync is intolerant of clock drift. Chrony ships enabled; just confirm `System clock synchronized: yes`.

---

## Part 3 - Form the Proxmox Cluster

On `pve-hp1` (make the beefier class of machine the first node):

```bash
pvecm create fortworth   # name it whatever you like
```

On every other node (`pve-hp2`, `pve-hp3`, `pve-svc`):

```bash
pvecm add 192.168.1.11
```

Verify from any node:

```bash
pvecm status    # expect: Quorate: Yes, Nodes: 4 (or 3)
```

You now manage everything from one web UI (https://192.168.1.11:8006). Two rules of Proxmox cluster life:

- Never let the cluster drop below quorum while you are making changes (e.g. do not shut two nodes down for RAM upgrades simultaneously in a 3-node cluster).
- Node hostnames and IPs are effectively permanent after joining. Get them right first.

---

## Part 4 - Ubuntu Cloud-Init VM Template

Build once on `pve-hp1`, clone everywhere.

```bash
# download Ubuntu 24.04 cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# create template VM (id 9000)
qm create 9000 --name ubuntu-2404-tmpl --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --agent enabled=1 \
  --cpu host --ostype l26
qm set 9000 --scsi0 local-lvm:0,import-from=$(pwd)/noble-server-cloudimg-amd64.img
qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
qm template 9000
```

`--cpu host` matters: it passes through the i5's real instruction set instead of a lowest-common-denominator virtual CPU, which k3s and Postgres both appreciate. It also means VMs cannot live-migrate between the Intel HPs and the AMD KAMRUI, which is fine because K8s VMs stay on the HPs anyway.

Migrate/clone the template to the other HP nodes (right-click > Clone works, or keep the template on hp1 and clone across nodes with `--target`).

---

## Part 5 - Create the k3s VMs

One VM per HP node. Sizing leaves the Proxmox host ~2 threads and ~7GB headroom:

| Setting | Value |
|---|---|
| vCPU | 5 (of 6) |
| RAM | 24576 MB (24GB, no ballooning) |
| Disk | 120GB+ (more if you upgraded NVMe and plan Longhorn) |
| Network | vmbr0, virtio |

Per node (adjust VM id, name, IP):

```bash
qm clone 9000 201 --name k3s-1 --full
qm resize 201 scsi0 +117G
qm set 201 --cores 5 --memory 24576 --balloon 0
qm set 201 --ipconfig0 ip=192.168.1.21/24,gw=192.168.1.1 \
  --ciuser camp --sshkeys ~/.ssh/id_ed25519.pub \
  --nameserver 192.168.1.1
qm set 201 --onboot 1
qm start 201
```

Repeat on hp2/hp3 as VM 202/203 with .22/.23. SSH in (`ssh camp@192.168.1.21`) and on **each** VM:

```bash
sudo apt update && sudo apt -y full-upgrade
sudo apt -y install qemu-guest-agent nfs-common open-iscsi   # iscsi needed later by Longhorn
sudo systemctl enable --now qemu-guest-agent iscsid
# k3s requirements
sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab
echo -e "net.bridge.bridge-nf-call-iptables=1\nnet.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-k8s.conf
sudo modprobe br_netfilter && echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
sudo sysctl --system
sudo reboot
```

---

## Part 6 - Install k3s (HA, embedded etcd, kube-vip)

### 6.1 kube-vip manifest (control-plane VIP) - on k3s-1 first

kube-vip gives you 192.168.1.20 as a floating API endpoint that survives any single server dying.

```bash
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
export VIP=192.168.1.20
export INTERFACE=eth0   # verify with: ip -br addr
KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases/latest | grep tag_name | cut -d '"' -f4)

curl -s https://kube-vip.io/manifests/rbac.yaml | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml >/dev/null

sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION 2>/dev/null || true
docker run --rm ghcr.io/kube-vip/kube-vip:$KVVERSION manifest daemonset \
  --interface $INTERFACE --address $VIP --inCluster --taint --controlplane \
  --arp --leaderElection 2>/dev/null | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml >/dev/null
```

(If docker/ctr are unavailable pre-k3s, generate the manifest on your workstation and scp it; it is just YAML.)

### 6.2 First server

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san 192.168.1.20 \
  --disable servicelb \
  --write-kubeconfig-mode 644
```

- `--cluster-init` starts embedded etcd.
- `--tls-san 192.168.1.20` puts the VIP on the API cert.
- `--disable servicelb` because MetalLB replaces k3s's built-in Klipper LB (MetalLB is the standard you want to learn).
- Traefik ingress stays enabled (default); it is genuinely good.

Grab the join token:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

### 6.3 Servers 2 and 3 (on k3s-2, k3s-3)

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://192.168.1.20:6443 \
  --token <NODE_TOKEN> \
  --tls-san 192.168.1.20 \
  --disable servicelb
```

**[2-HP variant]** Skip kube-vip entirely. k3s-1: same install minus `--tls-san`. k3s-2 joins as an agent:
`curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.21:6443 K3S_TOKEN=<token> sh -`

### 6.4 kubectl from your workstation

```bash
# on your Mac/PC
scp camp@192.168.1.21:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i '' 's/127.0.0.1/192.168.1.20/' ~/.kube/config   # VIP (or .21 in 2-HP variant)
kubectl get nodes -o wide   # expect 3 Ready control-plane,etcd,master nodes
```

Install `helm` on your workstation too (`brew install helm`).

### 6.5 MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl -n metallb-system wait --for=condition=ready pod --all --timeout=120s

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: lan-pool, namespace: metallb-system}
spec:
  addresses: [192.168.1.240-192.168.1.250]
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: lan-l2, namespace: metallb-system}
spec: {}
EOF
```

Now any `Service` of type `LoadBalancer` gets a real LAN IP. Sanity check the whole cluster:

```bash
kubectl create deploy hello --image=nginx --replicas=3
kubectl expose deploy hello --port 80 --type LoadBalancer
kubectl get svc hello    # visit the EXTERNAL-IP, then clean up:
kubectl delete svc,deploy hello
```

### 6.6 Storage

k3s ships `local-path` as the default StorageClass: PVCs bind to a directory on whichever node the pod lands on. Simple, fast, not replicated. Strategy:

- **Now:** keep local-path. Database durability comes from CloudNativePG replication (below), not the storage layer.
- **Later (recommended once comfortable):** install Longhorn (`helm install longhorn longhorn/longhorn -n longhorn-system --create-namespace`) for replicated block storage and snapshot/backup UX. It needs the `open-iscsi` you already installed and real disk headroom.

---

## Part 7 - Cluster Core Services for Adjutant

Namespace and secrets first:

```bash
kubectl create namespace adjutant

kubectl -n adjutant create secret generic adjutant-secrets \
  --from-literal=TELEGRAM_BOT_TOKEN='...' \
  --from-literal=TELEGRAM_ALLOWED_USER_ID='...' \
  --from-literal=ANTHROPIC_API_KEY='...' \
  --from-literal=LITELLM_API_KEY='sk-local-anything' \
  --from-literal=PROXMOX_TOKEN_ID='adjutant@pve!readonly' \
  --from-literal=PROXMOX_TOKEN_SECRET='...'
```

### 7.1 PostgreSQL via CloudNativePG (with pgvector)

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml

cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: adjutant-pg, namespace: adjutant}
spec:
  instances: 2                      # primary + 1 streaming replica
  imageName: ghcr.io/tensorchord/cloudnative-pgvecto.rs:16-v0.3.0   # pg16 + vector
  storage: {size: 20Gi}
  bootstrap:
    initdb:
      database: adjutant
      owner: adjutant
      postInitSQL:
        - CREATE EXTENSION IF NOT EXISTS vector;
        - CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF
```

CNPG creates services `adjutant-pg-rw` (primary) and `adjutant-pg-ro` (replicas) and a secret `adjutant-pg-app` containing the app user's credentials. Your `DATABASE_URL` becomes:
`postgresql+asyncpg://adjutant:$(password)@adjutant-pg-rw.adjutant.svc:5432/adjutant`

With 2 instances on local-path storage, a node failure means CNPG promotes the replica on the surviving node. That is the durability model; verify it once by draining a node on purpose.

### 7.2 Redis

Adjutant uses Redis as broker + pub/sub, all reconstructable state, so a single non-persistent instance is correct:

```yaml
# redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis, namespace: adjutant}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template:
    metadata: {labels: {app: redis}}
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          args: ["--maxmemory", "512mb", "--maxmemory-policy", "noeviction"]
          ports: [{containerPort: 6379}]
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits: {memory: 640Mi}
---
apiVersion: v1
kind: Service
metadata: {name: redis, namespace: adjutant}
spec:
  selector: {app: redis}
  ports: [{port: 6379}]
```

### 7.3 LiteLLM proxy (in-cluster for now)

Until the 3090 node exists, every alias maps to Anthropic. When the GPU node arrives, you change this ConfigMap and nothing in Adjutant moves.

```yaml
# litellm.yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: litellm-config, namespace: adjutant}
data:
  config.yaml: |
    model_list:
      - model_name: fast
        litellm_params: {model: anthropic/claude-haiku-4-5, api_key: os.environ/ANTHROPIC_API_KEY}
      - model_name: worker
        litellm_params: {model: anthropic/claude-sonnet-4-6, api_key: os.environ/ANTHROPIC_API_KEY}
      - model_name: planner
        litellm_params: {model: anthropic/claude-sonnet-4-6, api_key: os.environ/ANTHROPIC_API_KEY}
      # GPU-node future state, uncomment and point at the Ollama VM:
      # - model_name: fast
      #   litellm_params: {model: ollama/qwen2.5:7b-instruct, api_base: http://192.168.1.30:11434}
    general_settings:
      master_key: os.environ/LITELLM_API_KEY
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: litellm, namespace: adjutant}
spec:
  replicas: 1
  selector: {matchLabels: {app: litellm}}
  template:
    metadata: {labels: {app: litellm}}
    spec:
      containers:
        - name: litellm
          image: ghcr.io/berriai/litellm:main-latest
          args: ["--config", "/config/config.yaml", "--port", "4000"]
          envFrom: [{secretRef: {name: adjutant-secrets}}]
          volumeMounts: [{name: cfg, mountPath: /config}]
          ports: [{containerPort: 4000}]
          resources: {requests: {cpu: 100m, memory: 256Mi}}
      volumes: [{name: cfg, configMap: {name: litellm-config}}]
---
apiVersion: v1
kind: Service
metadata: {name: litellm, namespace: adjutant}
spec:
  selector: {app: litellm}
  ports: [{port: 4000}]
```

Embeddings note: there is no local embed model yet. Two options until the GPU node: (a) run a tiny CPU Ollama deployment just for `nomic-embed-text` (it is fast on CPU), or (b) use an API embedding model via LiteLLM and change the `vector(768)` dimension in the schema to match. Option (a) keeps the schema untouched and is what I would do.

---

## Part 8 - Containerize and Deploy Adjutant

### 8.1 Claude Code prompt (run in the adjutant repo)

Add this to PROMPTS.md as Prompt 13 and run it:

```
Read CLAUDE.md. Add Kubernetes deployment support:

1. A multi-stage Dockerfile: builder stage runs uv sync into a venv;
   runtime stage on python:3.12-slim copies the venv and app, creates a
   non-root user, and supports three entrypoints selected by the container
   arg: api (uvicorn app.main:app), worker (celery -A app.scheduler worker
   --loglevel=info), beat (celery -A app.scheduler beat).
2. A .dockerignore and a GitHub Actions workflow that builds and pushes
   ghcr.io/camptwright/adjutant:sha-<sha> and :latest on push to main.
3. k8s/ directory with plain manifests for namespace-scoped deploys in
   'adjutant': deployment-api.yaml (1 replica, runs api entrypoint,
   includes the Telegram bot in the FastAPI lifespan, liveness/readiness
   probes hitting /health), deployment-worker.yaml (1 replica, worker),
   deployment-beat.yaml (1 replica, beat, and a strict single-replica
   strategy: Recreate), and a pre-deploy Job manifest job-migrate.yaml that
   runs alembic upgrade head. All read env from the adjutant-secrets secret
   plus a ConfigMap adjutant-config for non-secret settings (DATABASE_URL
   assembled from the CNPG adjutant-pg-app secret via env valueFrom,
   REDIS_URL=redis://redis:6379/0, LITELLM_BASE_URL=http://litellm:4000/v1).
   Set resource requests: api 250m/512Mi, worker 500m/1Gi, beat 50m/128Mi.
4. A k8s/kustomization.yaml tying it together and a Makefile target
   'make deploy' that applies the migration job, waits for completion,
   then applies the rest.

Constraint: Telegram uses polling, so nothing needs an Ingress or public
exposure. There must never be two beat replicas or two api replicas
(duplicate Telegram pollers); enforce replicas: 1 and Recreate strategy on
both.
```

### 8.2 Deploy

```bash
# one-time: let the cluster pull from GHCR if the repo is private
kubectl -n adjutant create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=camptwright \
  --docker-password=<github_PAT_with_read:packages>

kubectl apply -f redis.yaml -f litellm.yaml
make deploy   # migration job, then api/worker/beat

kubectl -n adjutant get pods
kubectl -n adjutant logs deploy/adjutant-api -f
```

Then message the Telegram bot the Phase 1 smoke test from PROMPTS.md. Note the pleasing recursion: the Infra agent you deploy on this cluster can be pointed at this cluster's own Proxmox API, so Adjutant's first job is monitoring the machines it lives on.

### 8.3 Kubernetes gotchas specific to this app

- **Two Telegram pollers = 409 Conflict errors from Telegram.** This is why api is pinned to 1 replica with Recreate. If you ever scale the api, move the bot into its own single-replica deployment.
- **Celery beat must also be exactly 1** or schedules double-fire (the atomic last_run_at guard in Prompt 9 protects you, but do not rely on it).
- **The infra agent's SSH key** becomes a K8s secret mounted at /app/keys. Generate a dedicated `adjutant_ed25519` keypair; authorize it only on hosts you want the agent reaching.

---

## Part 9 - Operations

- **Proxmox backups:** Datacenter > Backup, nightly vzdump of the k3s VMs to a directory on pve-svc (or a cheap USB disk on it). Later: Proxmox Backup Server as an LXC on pve-svc for dedup + incrementals.
- **Postgres backups:** CNPG supports scheduled base backups to S3-compatible storage; a MinIO LXC on pve-svc or Backblaze B2 both work. Do this before Adjutant's memory becomes something you would miss.
- **Upgrades:** Proxmox via apt per node, one at a time, keeping quorum. k3s: upgrade servers one at a time with the same install script pinned to a version (`INSTALL_K3S_VERSION=`); etcd HA means zero downtime.
- **Monitoring (optional but great K8s learning):** `helm install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace`, expose Grafana via MetalLB. Budget ~2GB RAM for it.
- **Node maintenance:** `kubectl drain k3s-2 --ignore-daemonsets --delete-emptydir-data`, do the work, `kubectl uncordon k3s-2`. Watch CNPG fail over during the drain once, deliberately, so the first time is not a surprise.

## Part 10 - Future GPU Node (parked, but so the design is honest)

When the 3090 box arrives: it joins Proxmox as `pve-gpu` (cluster votes go 5 or 4, still fine), gets an Ubuntu VM with PCIe passthrough of the 3090 running Ollama, and you edit exactly one thing: the litellm-config ConfigMap, remapping `fast`/`worker`/`embed` to `ollama/...` at the VM's IP, then `kubectl rollout restart deploy/litellm -n adjutant`. Adjutant itself never knows anything changed. That is the payoff of rule 1 in CLAUDE.md.

---

## Build-Order Checklist

0. [ ] Own router installed behind apartment jack, private LAN up, DHCP reservations set (Part 0.5)
1. [ ] NVMe upgrades in HPs (optional, recommended)
2. [ ] BIOS: VT-x/VT-d, power-on-after-loss (all nodes)
3. [ ] Proxmox installed, repos fixed, updated (all nodes)
4. [ ] Cluster formed, quorate
5. [ ] Cloud-init template built
6. [ ] 3 k3s VMs created, prepped, rebooted
7. [ ] kube-vip manifest staged, k3s server 1 up
8. [ ] Servers 2-3 joined, kubectl works from workstation via VIP
9. [ ] MetalLB installed, nginx smoke test passed
10. [ ] CNPG + adjutant-pg cluster healthy (kubectl -n adjutant get cluster)
11. [ ] Redis + LiteLLM deployed
12. [ ] Prompt 13 run, image on GHCR
13. [ ] make deploy, pods green, Telegram smoke test passed
14. [ ] Backups scheduled (vzdump + CNPG)
