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
6. Release bundle allowlist currently includes shell entrypoints only. New Python support modules require explicit inclusion and archive contract tests.

## Evidence limits

This inventory is source inspection, not a live-state verification. No deployment or secret access was performed. Tasks1 discovery is complete for the current release orchestration; detailed phase contracts and E2E proof remain required before claiming the entire installer works.
