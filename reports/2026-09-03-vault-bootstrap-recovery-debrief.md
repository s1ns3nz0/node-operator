# Clean-room debrief: Vault bootstrap and recovery contract

Task: `2026-09-03-vault-bootstrap-recovery`
Review scope: completed task bundle, diff `5098545..d74ac8f`, and the recorded successful checks only.

## Outcome

The change adds a non-secret, declarative, fail-closed readiness contract for
the Vault release path. Release credentials are contractually denied unless all
eight ordered phases have passed evidence and every deny-path probe is denied.
The added JSON contract, accompanying GitOps documentation, and structural CI
test consistently encode that boundary.

The ordered contract covers private connectivity and TLS; the operator-only
initialize/unseal boundary; audit delivery; encrypted Raft snapshot and
isolated restore-drill evidence; GitHub JWT and dynamic AWS release access;
AWS-authenticated CodeBuild signing; and Transit signing/verification. It
limits retained evidence to non-secret correlation fields and explicitly
forbids tokens, keys, credentials, recovery/unseal material, private keys, and
Transit signatures.

## Evidence reviewed

The task bundle records successful completion of:

- the Vault bootstrap and recovery contract test;
- the Vault GitOps contract;
- the Vault release JWT and dynamic AWS contract;
- the Vault release verification gate;
- harness task-graph validation; and
- whitespace validation with `git diff --check`.

The implementation diff adds the bootstrap/recovery contract, human-readable
operator guidance, a fail-closed structural test, and the corresponding npm
script. The structural test checks exact phase order, the sign/verify-only
Transit permission boundary, evidence allow/deny lists, required linked
artifacts, and the absence of executable or live-deployment fields and
commands in the declarative contract.

## Live-operation boundary

This review does **not** establish that a Vault instance was initialized,
unsealed, configured, audited, snapshotted, or restored. No live Vault, cloud,
credential, AWS, or production operation is represented by the recorded
evidence. In particular, audit-device delivery, snapshot encryption and
retention, and an isolated restore drill remain environment-owned work to be
performed only under a separately authorized live rollout.

Accordingly, this change is an implementation prerequisite and readiness
evidence contract, not deployment authorization. Release credentials remain
denied until an approved operator supplies the required non-secret passed and
deny-path evidence during that future rollout.

## Clean-room assessment

Within the restricted review scope, the change matches its stated objective:
it creates an ordered, non-secret, fail-closed declarative contract without
introducing commands that initialize, unseal, configure, apply, or otherwise
operate a live Vault. The remaining live-control verification is intentionally
out of scope and requires separate authorization.
