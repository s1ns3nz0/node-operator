# Reproducible release foundation

1. Record a redacted Hoodi release baseline: source revision, pinned client
   chart revision, and required non-secret configuration shape.
2. Add a release-owned command that verifies an extracted bundle before it can
   run Terraform, and exposes plan/apply as explicit operations.
3. Add a non-secret Hoodi input template that rejects temporary SSM flags from
   the baseline deployment path.
4. Extend the deterministic bundle boundary to carry the bootstrap command and
   its release contract, then test extraction and command behavior.
5. Document the required Terraform state migration from the legacy embedded
   temporary SSM resources to a future isolated operations-access state. Do not
   mutate live state in this task.

The release deploys UC-1 and the non-secret UC-2 through UC-5 contracts only.
Vault initialization, custody ceremonies, validator keys, and signer duties
remain explicitly outside the bundle.
