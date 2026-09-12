# Node Operator Current-State Handoff

Date: 2026-09-11 (Asia/Seoul)

## Purpose of this handoff

The next implementation target is a single interactive entrypoint that can
prepare and deploy a Hoodi validator environment from a clean or partially
existing account. Implementation is intentionally deferred in this turn. This
file records the current repository state, the Vault boundary already designed,
and the work that must be completed before that entrypoint is considered ready.

## Current state

- The repository contains separate release, infrastructure, Vault, custody,
  cutover, activation, evidence, and observation scripts.
- `scripts/release/hoodi-validator-release.sh` is the main release wrapper for
  verification, interactive preparation, infrastructure/deployment staging,
  evidence, and access preparation. It deliberately stops before Vault
  recovery, custody, GitOps publication, irreversible cutover, and validator
  activation.
- `scripts/release/node-operator-release.sh` handles bundle verification and
  zero-resource Terraform bootstrap. It does not initialize/restore Vault,
  create SSM access, publish GitOps, read secrets, or activate a validator.
- Vault v2 preparation and activation are implemented as separate ceremonies.
  The relevant source-of-truth scripts are:
  - `scripts/ops/recover-and-bootstrap-hoodi-vault-v2.sh`
  - `scripts/ops/prepare-hoodi-vault-v2-transport.sh`
  - `scripts/ops/activate-hoodi-vault-v2-roles.sh`
  - `scripts/ops/copy-hoodi-custody-to-runtime-v2.sh`
  - `scripts/ops/recover-and-onboard-hoodi-validator-keystore.sh`
- Live Vault cutover is split into engine and validator paths, with a separate
  convergence check and an explicit finalization step:
  - `scripts/ops/preflight-live-vault-cutover.sh`
  - `scripts/ops/apply-live-engine-vault-cutover.sh`
  - `scripts/ops/apply-live-validator-vault-cutover.sh`
  - `scripts/ops/verify-live-vault-cutover-convergence.sh`
  - `scripts/ops/finalize-live-vault-secret-cutover.sh`
- Validator activation is intentionally separate and fail-closed through
  `scripts/ops/activate-hoodi-validator-client.sh`.
- Private EKS/Vault connectivity is intentionally short-lived and wrapped by
  `scripts/ops/with-private-eks.sh`, `with-private-vault.sh`, and
  `with-private-vault-operator.sh`.
- UC-1 through UC-4 have been treated as the completed validation scope in the
  current workstream. UC-5 remains incomplete when its guarded ceremony cannot
  establish private Beacon readiness or a fresh finalized duty; it must not be
  silently reported as complete.
- CI/workflow consolidation has been an active workstream. The repository still
  has multiple purpose-specific workflows under `.github/workflows/`; no further
  consolidation or deletion should be assumed from this handoff alone.
- Existing user/agent changes in the worktree were preserved. This handoff does
  not claim that unrelated dirty files are ready to commit.

## Vault secret boundary to preserve

The single entrypoint must keep these values in Vault or in the existing
short-lived ceremony channel; they must never be placed in command arguments,
Git, CI artifacts, Kubernetes manifests, or durable evidence:

- validator keystore material and keystore password;
- signer server private key, PKCS#12 material, and password;
- validator client private key and client certificate material;
- Engine API JWT;
- slashing database password and other runtime database credentials;
- Vault recovery shares, generated administrator tokens, and one-time custody
  credentials.

Only public or non-sensitive outputs may be retained in evidence, including
public CA certificates, known-client fingerprints, image digests, resource
identity, phase status, and hashes of approved artifacts.

## Required single-entrypoint design

The entrypoint should be an orchestrator that calls the existing bounded
scripts. It should not duplicate every Vault/API operation into one giant
shell file. It must support:

1. `prepare`, `run`, `resume`, and `status` commands;
2. fresh-account and existing-environment modes;
3. interactive prompts for recovery shares, keystore passwords, custody input,
   deposit confirmation, and activation gates;
4. non-interactive resume only when the required preparation evidence already
   exists;
5. idempotent phase checkpoints and fail-closed handling of stale or mismatched
   state;
6. no secret values in logs, state, evidence, or process arguments;
7. explicit confirmation before destructive secret finalization, validator
   activation, or any external mutation;
8. short-lived SSM/Vault sessions with cleanup on success, failure, and signal;
9. a final summary that reports completed, blocked, and pending phases without
   exposing credentials.

## Work to perform next

### Phase A: contract and state model

1. Define the public input contract: AWS account/region, EKS cluster, validator
   set, public key, withdrawal address, approved image digests, network CIDR,
   bundle root, and evidence directory.
2. Define `fresh` versus `existing` behavior and fail-closed adoption rules.
3. Define the phase/state schema, checkpoint names, resume rules, stale-state
   detection, and evidence directory layout.
4. Define the human-approval gates and the exact inputs that may be typed only
   into an interactive terminal.

### Phase B: orchestrator implementation

5. Add one top-level release/ops entrypoint with robust argument parsing,
   `set -Eeuo pipefail`, path validation, signal cleanup, and shellcheck-clean
   behavior.
6. Add dependency, AWS identity, bundle, EKS private endpoint, SSM, Vault
   health, and local keystore preflight checks.
7. Wire preparation to the existing zero-resource and Hoodi deployment input
   scripts, then persist only non-sensitive state.
8. Wire infrastructure and SSM access preparation/apply for the selected mode.
9. Wire staged Kubernetes deployment and verification.
10. Wire Vault v2 bootstrap/prepare/activate, custody preservation, keystore
    onboarding, and generated-root revocation checks.
11. Wire engine and validator Vault cutover, convergence verification, and keep
    destructive legacy-secret deletion behind an explicit confirmation flag.
12. Wire deposit evidence, signer evidence, Beacon evidence, validator client
    activation, and post-activation duty observation.
13. Keep UC-5 as an opt-in guarded phase requiring fresh normal-duty evidence;
    never run it as an implicit part of the normal deployment path.
14. Implement `resume` and `status` output from the checkpoint state without
    printing tokens, keys, passwords, or raw Vault responses.

### Phase C: validation and documentation

15. Add local tests for argument validation, duplicate/missing keystores,
    evidence mismatch, stale state, wrong account/region, phase ordering, and
    secret-leak prevention.
16. Run shellcheck and the repository harness checks; record only non-sensitive
    evidence.
17. Document the clean-account quick start, every prompt/gate, resume/recovery,
    rollback boundaries, and the difference between one command and one human
    approval.
18. Perform an independent security review of the orchestrator and integrate
    the findings before any live deployment or release publication.

## Explicitly out of scope for this handoff

- No live EKS/Vault mutation, deletion, deployment, publication, merge, or
  secret rotation was performed while creating this file.
- No claim is made that UC-5 is complete.
- No claim is made that all current workflows are already reduced to the final
  desired count.
- No existing ceremony script should be deleted until the new entrypoint has
  passed local, dry-run, resume, and failure-cleanup tests.

## Success criteria for the next implementation slice

From a clean checkout and an account with no related resources, an operator can
run one documented command, answer the required interactive prompts, resume
after a failure, and reach a truthful final status. Every Vault-bound secret is
written through the existing guarded ceremonies, every destructive or external
action has an explicit gate, and the evidence bundle contains only
non-sensitive, reproducible facts.
