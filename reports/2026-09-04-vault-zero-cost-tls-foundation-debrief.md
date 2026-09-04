# Clean-room debrief: Vault zero-cost TLS foundation

Task: `2026-09-04-vault-zero-cost-tls-foundation`  
Review basis: task bundle, the task-contract implementation-file diff from
`e0ed8bd..eb91774`, and the stipulated local checks only. No live environment,
cloud, Kubernetes, Vault, Secret, or production access was used.

## Observed evidence

- The task contract scopes the design to a namespaced, cluster-local Vault CA,
  private ECR delivery, immutable digest/checksum pins, and no manually created
  or inspected Secret material. It explicitly prohibits mirror execution and
  live apply actions.
- The reviewed diff adds an approved cert-manager v1.21.1 chart archive record
  with SHA-256 and OCI manifest digest, plus four digest-pinned cert-manager
  runtime images, all destined for the private `cert-manager` ECR boundary.
- The reviewed chart workflow validates the checked-in chart source/version,
  SHA-256, publisher signature, and post-push ECR manifest digest before it
  reports success. The general OCI-mirror workflow admits `cert-manager` only
  when an approved digest record matches its destination.
- The reviewed values file references a private ECR repository and supplies
  explicit immutable tags and `sha256` digests for controller, webhook,
  cainjector, and startup API check images.
- The reviewed Vault TLS manifest contains cert-manager `Issuer` and
  `Certificate` resources for `vault-internal-ca` and `vault-tls`; it contains
  no Kubernetes `Secret` resource or certificate/private-key value. Its server
  certificate includes Vault service and StatefulSet peer DNS names and uses
  `rotationPolicy: Always`.
- The reviewed Terraform change pre-creates separate immutable,
  scan-on-push private ECR repositories for the cert-manager image and chart
  paths. It does not add a public network, NAT, or public-egress construct in
  the scoped diff.
- The task bundle's evidence records a passed official metadata/signature check,
  private-delivery contract check, offline Terraform fixture plan, and Vault
  internal-CA contract. Those are prior-task evidence, not checks independently
  rerun for this debrief.
- The following checks were independently run and passed:

  - `npm run harness:check` — 47 task graphs checked.
  - `npm run test:gitops-oci-mirror-contract`
  - `npm run test:cert-manager-chart-mirror-contract`
  - `npm run test:vault-internal-tls-contract`
  - `git diff --check e0ed8bd..eb91774` — exited successfully with no output.

## Inference

The implementation is consistent with the stated zero-additional-AWS-cost
intent: it establishes a cluster-local, Vault-scoped issuance path and private
artifact-delivery controls without placing key material in the repository.
The local checks give good evidence for the declared source and invariant
contracts, but do not establish that a private ECR mirror has been populated,
that Terraform has been applied, or that cert-manager/Vault resources are ready
in a cluster.

## Verdict and blockers

No security blocker was identified in the reviewed scope, and the required
local checks pass.

An execution blocker intentionally remains: this task has no authority to run
the mirror workflows, apply Terraform or Kubernetes resources, or inspect the
resulting Secrets. A separately authorized saved-plan/live-execution task must
perform those actions through the private EKS path and verify readiness without
reading Secret data.
