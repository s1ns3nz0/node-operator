# Zero-cost private Vault TLS foundation

## Decision

Use cert-manager to bootstrap a private CA that is dedicated to Vault in this
cluster.  cert-manager, rather than an operator, writes and renews
`vault/vault-tls`.  AWS Private CA is deliberately excluded to avoid its
recurring charge for this portfolio environment.

This is transport security for private Vault API and Raft traffic, not a
replacement for a shared organizational PKI.  The CA key is a Kubernetes
Secret, so the design is intentionally bounded to this one Vault deployment.

## Execution sequence

1. Record the existing Vault TLS contract, private ECR conventions, cluster
   add-on compatibility, and required NetworkPolicy boundary.  The Luna recon
   found no cert-manager artifacts currently mirrored and no public egress.
2. Select a supported, pinned cert-manager release; obtain provenance and
   immutable image digests.  Extend the reviewed private artifact mirror so
   the chart and its controller, webhook, cainjector, and startup API check
   images are available from private ECR before installation.
3. Add reviewed values/manifests for a dedicated cert-manager namespace and a
   Vault-only CA hierarchy: SelfSigned is used solely to bootstrap the root,
   then a CA issuer signs the Vault leaf Certificate.  Keep all private-key
   material controller-managed and out of repository evidence.
4. Add Vault-scoped NetworkPolicies and client trust-distribution guidance.
   Do not mark the Vault Helm task deployable until the policy design and
   private artifact preflight pass.
5. Run local rendering and policy checks.  Then inspect the exact live plan
   and private paths before making an external change.  After installation,
   verify only conditions, object names, key names, private image references,
   and internal-only invariants.
6. Complete harness validation and obtain an independent clean-room Terra
   debrief from the completed bundle, scoped diff, and checks.

## Non-goals

No AWS Private CA, no public ingress, no Vault initialization/unseal, no
application rollout, no reading any Secret, and no cluster-wide CA service.

## Cost boundary

The design creates no AWS Private CA monthly charge.  It uses the existing
EKS and private ECR foundation; ordinary existing AWS storage/transfer costs
remain subject to the account's normal billing.
