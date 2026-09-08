# hoodi-001 recovery and UC-1 through UC-5 verification

## Safety sequence

1. Reconcile the existing public deposit receipt/Event and validator public key
   with the public-only runtime signer key. Never request key material.
2. Inspect the current namespace, signer/database/PVC, lease, client absence,
   GitOps source, and renderer inputs through read-only paths. Record sanitized
   identities and health only.
3. Correct the private duty observer so it follows the Beacon API request
   contract, checks current and next epochs, fails on HTTP errors, and never
   equates assignment with signed outcome. Correct private-EKS session cleanup
   so only the exact owned server-side SSM session is terminated.
4. Render the smallest restoration: reuse the existing signer, retained
   slashing database, and scoped fence; introduce exactly one zero-to-one
   validator client transition only after every activation gate passes.
5. Review the exact delivery diff, immutable images, namespace selectors,
   network policy, lease ownership, rollback-to-zero procedure, and evidence
   collection before any Git push, merge, reconciliation, or direct change.
6. Observe activation/index/duties through the private beacon and correlate
   actual validator-client and signer outcomes. Exercise UC-5 revoke/restore
   only while fenced, then require a first post-recovery duty.
7. Review UC-1 through UC-5 evidence, rerun any invalid or incomplete checks,
   and mark each as passed, pending an external chain gate, or blocked with the
   exact evidence gap. Do not create a graph or debrief.

## Mutation boundary

Read-only inspection and local fixes proceed first. External mutation begins
only after the integration owner states the exact GitOps or direct reviewed
path and proves the activation gates. Any key mismatch, deposit ambiguity,
missing PVC, slashing discontinuity, existing client, ambiguous lease holder,
unexpected resource delta, or secret-bearing output stops activation.

## Owned files

- Sol integration owner: this task contract/plan/evidence, restoration source
  and tests not delegated above, exact delivery review, live verification.
- Terra observer worker: duty observer and its focused contract test only.
- Terra SSM worker: private-EKS wrapper and its focused contract test only.
- Parent agent: public deposit receipt/Event and public-key reconciliation.
