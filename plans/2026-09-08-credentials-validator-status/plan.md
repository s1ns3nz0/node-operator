# Terraform credential cleanup and validator status

## Outcome

Make the isolated `ops-access` Terraform path able to use separate, short-lived
credentials for the S3 backend and AWS provider. The backend identity remains
scoped to encrypted state and locking, while provider refresh/apply uses an
explicit provider identity. No static credentials are accepted or persisted.
Prove the boundary with offline tests, then use existing identities only for a
read-only no-drift verification when admissible.

Reconcile the original Hoodi lifecycle T1-T18 graph against repository, prior
completion, sanitized live validator evidence, and public-chain evidence. Mark
observed facts separately from inferences. Deposit and custody are already
complete; do not request or create another deposit. UC-5 role revocation is a
limited PASS, not proof of post-recovery duty.

## Sequence and gates

1. Inspect every ops-access backend/provider invocation and existing tests.
2. Define a fail-closed interface for backend/provider profile separation.
3. Add tests first for forwarding, redaction, static-credential rejection, and
   backward-compatible ambient identity use; then implement the interface.
4. Run focused script checks, ShellCheck, release contracts, `harness:check`,
   and applicable `harness:verify` adapters.
5. If existing identities permit it, run one lock-free refresh-backed read-only
   plan against the canonical S3 key and retain only sanitized counts/digests.
   Do not grant `iam:GetRole` or any broader IAM permission in this task.
6. Produce the detailed T1-T18 status and dependency-aware next-task roadmap.
7. Obtain independent Terra review. Integrate any blocking findings.
8. Obtain a fresh clean-room debrief from the completed bundle, relevant diff,
   and checks only.

## Stop conditions

Stop before external mutation if completion would require an IAM change,
Terraform apply, workload deployment, access to secret-bearing objects, or a
new validator/wallet action. Do not touch the retired local recovery state.
