# Clean-room debrief: Vault chart manifest binding

## Scope and method

Independent review of the task bundle at
`plans/2026-09-04-vault-chart-manifest-binding/`, the diff
`4314aa0..HEAD`, and the affected allowlist, mirror workflow, Terraform,
fixtures, documentation, and contract checks. No external systems were
accessed; no Terraform plan, apply, CodeBuild run, deployment, secret
operation, merge, or publication was performed.

## Observed evidence

- The approved Vault chart record adds
  `ecrManifestDigest` for tag/version `0.31.0`:
  `sha256:85cfa6b40396a198a104fbf06c7cccaf75428db7201394f9061c272441bcd0e4`.
- The mirror workflow validates that value as a SHA-256 digest and, after
  pushing the approved and hash-verified archive, calls `ecr describe-images`
  for repository `node-operator-baseline-gitops-vault/vault` and tag `0.31.0`.
  The workflow exits unless the returned digest equals the allowlisted digest.
- `private-gitops.tf` defines `vault_chart` as
  `${local.name_prefix}-gitops-vault/vault` and documents that Helm OCI adds
  the chart name to the supplied registry location. This agrees with the
  mirror's push target `…/node-operator-baseline-gitops-vault` and its ECR
  lookup path.
- The bootstrap project receives the approved digest, requires it to be
  non-empty, resolves the same immutable-tag chart path with
  `ecr:DescribeImages`, and exits before Helm when that result differs. Helm
  uses the direct OCI reference
  `oci://…/vault@${var.vault_chart_manifest_digest}`, rather than a mutable
  version-tag selection.
- The bootstrap role's newly required `ecr:DescribeImages` is limited to the
  existing runtime-artifact repository and the distinct `vault_chart`
  repository. The remaining ECR actions in that statement are pull-only; no
  chart write permission was added. `ecr:GetAuthorizationToken` remains
  resource-unscoped, as required by the ECR IAM action model.
- Enabled, prepare, and revoke offline fixtures each supply the same
  digest-shaped value, and the deployment-phase documentation names the
  reviewed OCI-manifest gate.

## Checks run locally

- `scripts/ci/test-vault-chart-mirror-contract.sh` — pass.
- `scripts/ci/test-vault-chart-manifest-binding-contract.sh` — pass.
- `scripts/ci/test-vault-bootstrap-revocation-contract.sh` — pass.
- `terraform -chdir=infra/terraform fmt -check` — pass.
- `git diff --check 4314aa0..HEAD` — pass.
- `npm run harness:check` — pass (42 task graphs checked).

## Assessment

Accepted. The direct Helm OCI digest reference is syntactically and
topologically consistent with the configured ECR chart repository. The ECR
path is correct: the mirror pushes to the repository prefix and Helm resolves
the chart's `vault` name to the pre-created `...-gitops-vault/vault`
repository. The added read permission is least-privilege for the preflight:
`DescribeImages` is granted only on the chart and already-required Vault
artifact repositories, with no new write authority.

The binding is fail-closed at both relevant points: a mirror rerun must
reproduce the recorded manifest digest, and the executor compares the
immutable tag's current resolution before it invokes Helm, then uses the
approved manifest digest directly.

## Remaining gate

This review does not authorize an apply, CodeBuild invocation, or deployment.
The separately approved Prepare → Deploy → Revoke procedure remains required;
in particular, no deploy-stage action should occur until the explicit
authorization and the post-deploy cluster-admin revocation evidence are
available.
