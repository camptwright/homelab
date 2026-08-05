# LiteLLM and Beszel Security Hardening Plan

**Goal:** Deploy tested least-privilege controls and an accurate trust model
without breaking cross-LXC LLM access or Beszel monitoring.

## Tasks

- [x] Inventory live users, capabilities, root filesystem modes, listeners,
  socket mounts, LXC boundaries, firewall rules, and secret-file permissions.
- [x] Prove proposed controls with disposable LiteLLM and Beszel containers.
- [x] Add a failing security-contract test.
- [x] Add Compose controls, strong-key guidance, `SECURITY.md`, and CI coverage.
- [ ] Validate the full repository suite and GitHub Actions.
- [x] Tighten live secret-file and backup permissions. Rotate credentials
  exposed to the private hardening transcript as a separate coordinated task.
- [ ] Recreate only LiteLLM and
  Beszel agent with rollback backups.
- [ ] Verify authenticated LLM access, service health, Beszel telemetry, and
  unchanged unrelated workloads; then advance the parent pin.
