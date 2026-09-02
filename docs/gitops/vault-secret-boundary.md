# Vault secret boundary

Vault is the only runtime secret store for node-operator workloads. Terraform
must not receive or render secret values, and Argo CD Git repositories contain
only Vault policies, non-sensitive `SecretStore`/role configuration, and
workload references.

## Ownership

- Terraform creates only approved AWS prerequisites, including a dedicated KMS
  key for Vault auto-unseal and the narrowly scoped Pod Identity/IAM role.
- Argo CD installs and upgrades the pinned Vault chart after EKS readiness.
- Vault owns secret storage, policies, leases, and rotation.
- Workloads consume secrets through Vault Agent Injector or the CSI provider at
  runtime; Kubernetes Secret manifests containing values are prohibited.

## Bootstrap order

1. Apply and verify EKS infrastructure.
2. Install Vault through Argo CD with auto-unseal backed by the dedicated KMS key.
3. Configure Vault auth, policies, and roles using non-secret manifests.
4. Store secret values through an approved operator workflow, never Git or CI logs.
5. Deploy workloads and require Vault-backed injection plus Argo CD `Synced`/`Healthy`.

Vault tokens, recovery keys, unseal material, secret values, and kubeconfigs are
never committed to Git, Terraform state, CI artifacts, or compliance evidence.
