# Clean-room debrief: private Vault delivery

Task: `2026-09-04-vault-private-delivery`  
Reviewer: fresh Terra reviewer  
Disposition: **blocked; do not approve delivery-path apply, mirror, executor run, or Helm installation.**

## Scope and evidence reviewed

Read-only review of the task contract, plan, graph/evidence bundle, and the
Vault delivery changes: `infra/terraform/vault-bootstrap.tf`,
`infra/terraform/endpoints.tf`, `infra/terraform/private-gitops.tf`, the
offline fixture and plan test, the Vault bootstrap Dockerfile, toolchain
workflow/test, package script, and the existing GitOps OCI mirror
allowlist/workflow/contracts. No AWS, ECR, EKS, Kubernetes, secret, or log
access was performed. No deployment or Terraform apply was performed.

The bundle records passing offline-plan, toolchain-release, harness, and diff
whitespace checks. Those are observed claims in `evidence.json`, not evidence
that the private runtime inputs exist or that a temporary EKS association was
revoked.

## Blocking findings

1. **The required private artifact set cannot currently be supplied.** The
   private executor may pull only `private_gitops["vault"]`, and its image
   reference is correctly constrained to that repository. However,
   `.ci/gitops/approved-oci-artifacts.json` contains only Vault server and
   injector images for the `vault` destination. It contains neither the Vault
   Helm chart (`0.31.0`) nor `vault-bootstrap` toolchain image. Consequently
   the reviewed mirror workflow has no approved input with which to populate
   either artifact; the executor cannot meet the task's requirement that chart,
   runtime-image, and toolchain inputs are available from private ECR.

2. **The values template does not redirect Vault runtime images to private
   ECR.** `docs/gitops/vault-values.example.yaml` does not set the server or
   injector image repository/digest to the private Vault ECR repository. The
   Helm chart will therefore retain its upstream image locations despite the
   separate image entries in the mirror allowlist. This violates the
   private-only runtime-input constraint and would fail in the no-public-egress
   cluster.

3. **Cluster-admin is not staged or verifiably revoked.** The CodeBuild
   buildspec always performs `helm upgrade --install`; it has no render-only or
   prerequisite-only mode. The CodeBuild project precondition also requires
   `enable_vault_bootstrap_cluster_admin=true`, so the allowed pre-approval
   render/existence-verification phase cannot be created or run separately
   from the admin grant. The EKS policy association is only conditionally
   created/destroyed by a variable; no post-install revocation workflow,
   lifecycle guard, or validation proves its removal. The enabled-plan test
   asserts creation of cluster-admin, but never proves the disabled/revocation
   plan destroys it (and, per the evidence note, removes the project). This is
   insufficient for the task's explicitly required post-install removal.

4. **Toolchain build inputs are not fully pinned.** Although the base image
   and downloaded Helm/AWS CLI/kubectl artifacts are digest/checksum pinned,
   `apt-get install ca-certificates curl tar unzip` is version-unpinned. That
   leaves part of a security-critical toolchain build mutable, contrary to the
   task constraint that toolchain inputs are digest/version pinned.

## Additional review observations

- The executor security group is narrowly outbound on TCP/443 to the private
  EKS API/interface-endpoint groups and the S3 managed prefix list. Together
  with the VPC's lack of Internet/NAT routes, this is a sound public-egress
  direction. The current plan test checks only that no new IGW/NAT is planned;
  it does not inspect the runner's actual egress rules.
- IAM is generally limited to target-cluster description, ECR pull from the
  Vault repository, write-only project logs, and required CodeBuild ENI
  operations. `ecr:GetAuthorizationToken` and the ENI actions necessarily use
  `*`; the latter should remain justified and, where AWS supports it, narrowed
  with conditions.
- The buildspec checks only `vault-tls` existence/name and does not request
  secret data. The KMS key ARN interpolation is non-secret. No static AWS or
  Vault credential is introduced by the reviewed files.
- The test suite is largely textual/structural: it does not assert private
  image overrides, approved chart/toolchain allowlist entries, digest parity
  after mirroring, render-only behavior, failure when admin is disabled, or a
  removal plan after installation. A passing offline creation plan therefore
  does not close the findings above.

## Required remediation before reconsideration

1. Add the reviewed, digest-pinned Vault Helm chart and Vault bootstrap image
   to the approved mirror allowlist and establish deterministic destination
   tags/digests; retain evidence of destination-digest parity without raw
   credentials or logs.
2. Set all Vault chart runtime image references to the private ECR copies,
   pinned by digest, and test that no upstream registry remains.
3. Split prerequisite/render verification from the installation action; make
   the temporary dedicated cluster-admin association an explicitly approved
   installation-only phase. Add a fail-closed revocation action and a test/plan
   that proves the association (and any intended temporary executor) is absent
   afterwards.
4. Pin package-manager inputs or use a fully pinned base/toolchain approach,
   then extend the toolchain test to cover Vault bootstrap's input hash and
   workflow matrix entry.

Until these are addressed, the recorded checks are useful structural evidence
but are not sufficient approval evidence for the private Vault delivery path.
