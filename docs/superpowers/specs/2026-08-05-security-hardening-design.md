# LiteLLM and Beszel Security Hardening Design

## Goal

Reduce container privilege for the LLM gateway and monitoring agent while
making their unavoidable network/daemon trust explicit.

## LiteLLM controls

Run as the pinned image's `nonroot` UID/GID, make the root filesystem read-only,
provide only hardened temporary storage, drop every capability, prevent
privilege escalation, limit processes, add liveness, and publish only IPv4.
Keep private-LAN access because other LXCs are real consumers. The master key is
the authorization boundary; plaintext HTTP on the trusted LAN remains accepted
until a TLS/VPN proxy is justified.

## Beszel controls and accepted risk

Apply the compatible filesystem/capability/process controls but keep the agent
as root so it can open the root-owned Docker socket. State plainly that `:ro`
does not restrict Docker API methods and grants daemon-root authority. Do not
add an unverified socket proxy in this change.

## Secret handling

Require 0600 on both live environment files. GitHub ignores them, but CT110's
local-only historical commit contains `.env`; normalize that checkout in its
separate recoverability task without destructive Git operations.
