# Vault artifact authority

- Status: accepted
- User approval: explicitly approved removal of forced Vault digest substitutions and alignment to the approval catalog on 2026-09-13.
- Task: installer preflight and resume

## Conflict

`infra/terraform/vault-bootstrap.tf` rewrites the approved catalog's Vault server and injector digests to different values and supplies a fixed audit-relay digest. The server replacement also appears in `.ci/vault-agent-hardened/upstream.lock.json`, but only as a test-only compatibility server; that record is not runtime approval. The existing catalog and rendered consumers therefore cannot yet establish one approved mirroring contract.

## Accepted resolution

Remove the ad hoc image-digest substitutions and bind the workload renderer and mirror to the same release-approved source records. Keep operator-supplied private artifacts exact and independently verified. Do not weaken digest checks or publish new builds to fill missing evidence silently.

This decision authorizes implementation and offline verification, not changes to live Vault, keys, custody, or validator activation. Missing artifact authority remains a fail-closed condition; approval alignment does not authorize invented publication records.

## Implementation verification

The local implementation derives server, agent and injector image references from the selected catalog and applies their validated Helm overlay last. Runtime digest substitution literals have been removed. The legacy platform handoff also binds the bootstrap executor, audit relay and chart to the publication index and deployment mirror receipt before planning.

Offline tests cover the approved values, a synthetic alternate catalog, rejection of missing or incorrect overlays, and rejection of an unapproved bootstrap executor. Independent review confirmed the executor-binding correction. No live deployment was performed.

This is not yet a complete release-installer delivery: bundle assembly must still materialize the publication index and the legacy deployment must produce its verified mirror receipt. Missing evidence stops the platform step without substituting an image.
