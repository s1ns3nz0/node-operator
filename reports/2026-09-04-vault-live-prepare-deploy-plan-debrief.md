# Clean-room debrief: live Vault/EKS prepare and deploy plan

## Disposition

Conditionally accepted as a plan-only artifact. It preserves the separate
prepare, temporary-admin deploy, and immediate revoke approvals; prohibits
Vault initialization, unseal, secret handling, and live actions; and requires
post-revoke verification before release signing.

It is not complete enough to authorize a live deployment. The live blocker is
the Vault chart identity: the proposed CodeBuild command selects the OCI chart
with `--version 0.31.0`, which is a mutable tag, while the plan requires only
that version and an unspecified approved archive. The plan must require the
reviewed private-ECR OCI manifest digest, bind it to the approved chart input
used at deployment (or attest immediately before execution that the approved
tag resolves to that exact digest), and reject a mismatch. A chart source
archive SHA-256 or toolchain image digest is not by itself an immutable binding
of the chart artifact Helm installs from ECR.

## Observed evidence

- The task bundle has the required contract, plan, graph, and evidence files;
  it records no external actions.
- `infra/terraform/vault-bootstrap.tf` creates the cluster-admin association
  only when both bootstrap flags are true. Its embedded buildspec installs the
  chart, waits for pods, checks only TLS Secret existence, and performs no
  Vault initialization or unseal operation.
- `docs/gitops/vault-bootstrap-phases.md` and
  `scripts/ci/verify-vault-bootstrap-revocation.sh` specify a separate revoke
  apply and verify absence of `AmazonEKSClusterAdminPolicy` for the dedicated
  role.
- The prior remediation debrief reports offline contract evidence but also
  reports the policy-adapter set was unavailable; this plan correctly retains a
  runnable policy-adapter evidence set as a precondition.

## Required corrections and remaining live gates

1. Add the OCI chart manifest-digest binding above to Gate 0/Gate 2 and the
   required handoff evidence. Do not approve CodeBuild until it is satisfied.
2. Retain the plan's existing separate human approvals for the exact saved
   Gate 1 plan, Gate 2 plan, and one-purpose CodeBuild invocation; then require
   the fresh Gate 4 revoke plan and successful absence verifier.
3. The current runnable policy-adapter evidence set, non-sensitive live plan
   review, external TLS/Pod Identity/KMS/network/audit/backup operator
   attestations, deployment health evidence, and post-revoke result remain
   live-stage blockers. None were independently observed here.

## Review scope

Read-only clean-room review of the supplied task bundle, the referenced prior
debrief, and the Terraform/GitOps/revocation artifacts needed to validate the
plan. No plans, external systems, or live operations were executed.
