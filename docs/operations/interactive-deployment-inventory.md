# Existing deployment inventory (v0.1.20)

## Reusable interfaces

| Boundary | Existing source | Current behavior / integration gap |
| --- | --- | --- |
| Preparation | `scripts/release/hoodi-validator-release.sh:90` | STS account and AZ discovery exist; prompts key/address, four private image digests and public /32 too early. AWS profile and deployment name need consistent propagation. |
| Infrastructure | `scripts/release/node-operator-release.sh:121` | `zero apply` builds backend, foundation and baseline. Reconcile existing outputs instead of blindly retrying. |
| Deployment | `scripts/release/hoodi-validator-release.sh:161` | Chains infrastructure, separate ops state apply and zero-replica staging. Does not initialize Vault or publish GitOps. New orchestration must preserve explicit SSM approval. |
| Private EKS | `scripts/ops/with-private-eks.sh:23` | Supports ephemeral session/kubeconfig but has a default live instance ID. Installer must always pass discovered account/Region/cluster/instance; never inherit production defaults. |
| Private Vault | `scripts/ops/with-private-vault.sh:16` | CA-verified port-forward to vault-active; assumes namespace vault and pod vault-0. Fresh phase must provide verified deployment outputs and healthy Vault first. |
| Runtime v2 | `scripts/ops/recover-and-bootstrap-hoodi-vault-v2.sh:79` | Composes runtime KV/PKI, Engine JWT and workload roles but requires initialized, unsealed Vault and recovery auth. |
| Custody | `scripts/release/hoodi-validator-release.sh:202` | Existing onboarding writes runtime secrets and public known-client ConfigMap; does not start workloads. |
| Activation | `scripts/release/hoodi-validator-release.sh:243` | Guarded activation requires independent deposit/private/signer evidence and explicit key/address confirmation. Preserve these checks. |

## Fresh installation blockers

1. Baseline disables Vault runner and temporary cluster-admin. Vault chart bootstrap is a separate Terraform/CodeBuild path (`infra/terraform/vault-bootstrap.tf:147`). It needs private artifacts, subnets and Vault TLS bootstrap. Resolve the artifact/auth/TLS dependency ordering before applying.
2. Existing recovery commands cannot initialize a new Vault. `docs/gitops/vault-bootstrap-recovery-contract.md` explicitly excludes init/unseal; implement a new authorized ceremony rather than pretending recovery is initialization.
3. `release/hoodi-release-contract.json` still declares Seoul while interfaces permit Tokyo. Static Prysm/Nethermind manifests embed account 106760547719 and Seoul artifacts/AZs. Render from target-specific verified outputs; do not reuse those values for fresh installs.
4. Secret source of truth is `docs/security/vault-v2-secret-inventory.md`. Inventory and validate the entire document before task9, not only validator signing secrets.
5. GitOps publication and registry permissions still require independent adapters. Image destination digests are not first-run user inputs in the intended interface.
6. The baseline release did not include the new installer Python modules. The implementation branch now explicitly packages its four support modules and tests their archive presence; future modules must extend that allowlist and contract.

## Evidence limits

This inventory is source inspection, not a live-state verification. No deployment or secret access was performed. Tasks1 discovery is complete for the current release orchestration; detailed phase contracts and E2E proof remain required before claiming the entire installer works.

## Additional preflight and resume findings

- Backend names come from `infra/bootstrap-state/main.tf`: the state bucket
  includes account and region; the access-log bucket includes a truncated name
  and hash; the lock table is `${name}-terraform-lock`. Account bucket inventory
  cannot establish global S3 name availability or authorize resource adoption.
- A different region alone does not isolate IAM names. Foundation flow-log role
  `${name}-foundation-flow-logs` and baseline roles using `${name}-baseline-`
  require account-wide collision checks before provisioning.
- Baseline node capacity is intentionally not workload-ready: system desired
  size is one while consensus and execution desired sizes default to zero
  (`infra/terraform/variables.tf`). Workload deployment must explicitly connect
  capacity changes and their quota checks; EKS creation is not node completion.
- `scripts/release/node-operator-release.sh` currently rejects an incomplete
  bootstrap/foundation module directory and suggests a new work directory.
  The installer must reconcile the existing Terraform state instead; blindly
  starting over can collide with partially created infrastructure.
- The implementation branch now publishes Terraform output checkpoints only
  after a successful command and nonempty-object JSON validation. Failed queries
  preserve any prior checkpoint and do not create a false completion marker.
  On a completed bootstrap/foundation phase, resume now requires a successful
  no-change Terraform plan and exact semantic agreement between the saved
  output and Terraform state. Drift, invalid outputs, or missing original module
  directories stop before downstream apply. This does not repair legacy empty
  checkpoints or make interrupted resource creation automatically resumable.
- Bootstrap remote-state migration is not yet functional: the migration branch
  tests for an absent `.terraform` directory after initialization has created it,
  and the bootstrap source has no S3 backend declaration. Fixing only the branch
  condition is insufficient. The installer must explicitly preserve the initial
  local backend, introduce the S3 backend at the migration boundary, compare
  pre/post state identity, and verify a no-change plan before continuing. Merely
  adding an S3 block before `init -backend=false` is not an adequate design:
  disabling initialization does not configure a usable local backend for an
  S3-declared module. A marker or successful command alone cannot prove migration.
