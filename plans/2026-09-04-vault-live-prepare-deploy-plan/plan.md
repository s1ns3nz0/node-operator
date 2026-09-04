# Live Vault/EKS prepare and deploy approval plan

## Purpose and boundary

This is an execution plan only. It authorizes no cloud mutation and does not
authorize Vault initialization, unseal, secret handling, CodeBuild execution,
or Helm deployment. Each later phase requires its own explicit approval after
reviewing the exact saved Terraform plan and non-sensitive evidence.

## Gate 0 — repository and supply-chain readiness

Owner: Sol. Confirm the remediation bundle is accepted, the approved Vault
chart archive is present in private ECR at version `0.31.0`, the server,
injector, and bootstrap-toolchain artifacts retain approved immutable
references, and no source change is pending. Before any live plan or
CodeBuild approval, obtain the private-ECR OCI **manifest digest** resolved by
the approved `0.31.0` chart tag, record it in the reviewed execution bundle,
and bind the deployment to that exact digest (or attest immediately before the
one-purpose run that the immutable tag resolves to it). The source archive
SHA-256 does not replace this ECR-side binding. Re-run the applicable offline
contract checks and a runnable policy-adapter evidence set. Stop if an action,
chart manifest digest, policy adapter, or chart version differs from the
reviewed record.

## Gate 1 — live prepare plan review (no bootstrap execution)

Owner: Sol with Terra review. Generate a refresh-backed Terraform plan using
the approved private subnet IDs, the approved toolchain digest, and
`enable_vault_bootstrap_runner=true` with
`enable_vault_bootstrap_cluster_admin=false`. Save the exact plan artifact;
review it for only the private executor, EKS access entry without cluster
admin, private endpoint/SG rules, log group, and required private ECR/IAM
references. Reject any destroy, public network, public endpoint, static AWS
credential, unapproved input, or unrelated baseline change.

Human approval required before applying Gate 1. After apply, record only
non-sensitive resource/action counts and run the offline-compatible contract
checks. Do **not** start CodeBuild: its current buildspec includes Helm install
and is therefore a deploy action.

## Gate 2 — external prerequisites and deploy plan review

Owner: designated Vault operator plus Sol. Outside Git/Terraform state,
confirm that the `vault` namespace TLS secret exists with the required names
only; do not read or copy secret contents. Confirm Pod Identity/KMS, private
DNS and route availability, approved NetworkPolicies, audit/backup destination
ownership, and an operator-approved initialization/key-custody runbook.

Then create a new, refresh-backed Terraform plan with the identical reviewed
inputs but `enable_vault_bootstrap_cluster_admin=true`. The plan must differ
from Gate 1 only by the temporary `AmazonEKSClusterAdminPolicy` association
and necessary dependencies. Verify again that the chart tag resolves to the
Gate 0-recorded OCI manifest digest. A human must review and explicitly
approve this exact saved plan and the one-purpose CodeBuild invocation
separately.

## Gate 3 — bounded deployment and health evidence

Owner: approved operator. Apply the approved Gate 2 plan, start the dedicated
private CodeBuild project once, and retain non-sensitive outcome evidence.
The build performs the approved Helm release and waits for Vault pods. No
initialization, unseal, token creation, auth-method change, or secret read is
part of this automation.

Before any release-signing use, the operator must separately record: Helm
success, three Ready pods, sealed-state/leader health, TLS verification from
the private runner path, audit delivery, encrypted snapshot restore, and the
GitHub JWT/CodeBuild signer deny-path checks. Any failure is fail-closed.

## Gate 4 — immediate privilege revocation and verification

Owner: Sol. Create and apply a fresh plan reverting only
`enable_vault_bootstrap_cluster_admin=false`; review that it destroys the
temporary cluster-admin association and preserves no elevated alternative.
Run `verify-vault-bootstrap-revocation.sh` with the approved role input and
record the pass/fail result without exposing identifiers or API output. Do not
continue to release signing unless revocation passes.

## Rollback and stop conditions

- Before CodeBuild starts, reject the plan and make no changes when any gate
  fails.
- During installation, let Helm `--atomic` roll back its release on failure;
  preserve only non-sensitive failure classification.
- After any Gate 2 apply, priority is Gate 4 revocation; do not retry the
  deployment while temporary admin remains.
- Vault initialization, recovery keys, root tokens, TLS material, and audit
  payloads are never collected in this repository or task evidence.

## Required handoff evidence

The future execution bundle must contain reviewed saved-plan summaries,
non-sensitive resource/action counts, immutable artifact identifiers, the
CodeBuild outcome, the approved chart's private-ECR OCI manifest digest and
tag-to-digest resolution evidence, health/audit/restore attestations, and the
post-revoke verifier result. It must explicitly distinguish observed evidence
from operator attestation.
