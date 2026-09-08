# Hoodi validator status and next task

Status is reconciled from the original T1-T18 graph, repository evidence, the
prior ops-access completion, and sanitized read-only observations collected on
2026-09-08. `completed` means the task's stated deliverable is evidenced;
`in_progress` means a useful subset exists but an acceptance condition remains.
No status below authorizes deployment, signing, secret access, or a new deposit.

| ID | Reconciled status | Current proof | Remaining acceptance condition |
|---|---|---|---|
| T1 | completed | Evidence envelope and deny-list tests accept public records and reject forbidden credential fields. | Maintain the schema as later evidence types are added. |
| T2 | completed | Canonical validator-audit bucket is KMS-encrypted, versioned, Object-Locked for two years, and has public/TLS controls. | None for provisioning; restoration is T18. |
| T3 | completed from historical proof; not reverified this turn | The 2026-09-07 lifecycle evidence records private S3, CloudWatch Logs, and STS endpoints plus an applied workload-scoped Pod Identity association (`plans/2026-09-07-hoodi-validator-lifecycle/evidence.json`, observations 12 and 28). | Recheck endpoint/association health before any new delivery mutation. |
| T4 | completed from historical proof; not reverified this turn | The 2026-09-07 lifecycle evidence records Fluent Bit Ready on three eligible nodes and Nethermind, Prysm, and Vault audit records reaching their intended log groups (`plans/2026-09-07-hoodi-validator-lifecycle/evidence.json`, observation 28). | Recheck collector health before relying on it for a new live ceremony. |
| T5 | in_progress | Vault is healthy and Vault audit records reached the security log group. | Prove the full two-device, per-pod durable audit-volume, alert, and request-ID deduplication contract. |
| T6 | in_progress | Both log groups subscribe to Firehose; a live compressed object arrived with SSE-KMS and governance retention. | Prove the stated 90/365-day hot retention and recurring daily integrity manifests end to end. |
| T7 | in_progress | A local allowlist-only OpenSearch bulk builder works. | Deploy the derived index only after approval and prove a clean rebuild solely from the archive. |
| T8 | completed | Internal observer implementation exists; live Prysm reported a fresh head around slots 3888024-3888025 with `is_syncing=false`, `is_optimistic=false`, and `el_offline=false`. | Validator-specific state remains part of T15. |
| T9 | completed (implementation) | Etherscan observer and source-boundary contract exist. | Current public receipt/Event read was blocked by HTTP 403; independently reacquire public receipt and DepositContract event evidence. This is not evidence that the transaction failed. |
| T10 | completed (implementation) | Authenticated Beaconcha.in Hoodi observer and redacted response-hash behavior exist. | Use it only as corroboration once the validator is indexed. |
| T11 | in_progress | Private duty observer and singleton Ready-Pod fallback exist. | Correct and test the Beacon duty API contract: attester duties require the spec-defined request form; query both current and next epochs; fail on non-success HTTP; distinguish assignments from signed duty outcomes. |
| T12 | completed (implementation) | Internal/external authority and disagreement handling are defined and implemented locally. | Exercise it with real indexed-validator evidence after T15. |
| T13 | in_progress; ceremony reported done | The operator reports custody and the one intended deposit complete. Do not generate a new key or deposit. | Recover or recreate public-only attestation plus transaction receipt/Event correlation for the existing validator key; never request wallet/key material. Completion remains open until this public evidence is correlated. |
| T14 | in_progress | Operational signer and database are Running, the slashing PVC is Bound, and the validator client remains fenced. | Correlate the runtime signer public key with the existing custody/deposit public key and preserve authenticated slashing continuity evidence. |
| T15 | pending observation | The private beacon is synced, but the queried public key returned HTTP 404. | First prove key/receipt/Event identity. Then distinguish deposit processing/indexing/activation state. A 404 is not by itself an activation-queue result. |
| T16 | in_progress | Renderer and fencing contracts exist. There is no validator-client Deployment or Pod anywhere observed, and no matching custom resource. | After T14-T15 gates and explicit deployment authorization, start exactly one fenced client and correlate assignments with actual signer/client outcomes. |
| T17 | in_progress; limited UC-5 PASS | Revocation made the signer fail closed; restoration returned signer readiness; the client stayed fenced. | Prove slashing continuity and the first post-recovery duty. The limited role exercise alone is not full recovery completion. |
| T18 | in_progress | Several local failure-path contracts exist and the archive has a retained live object. | Run archive restoration, S3-only reindex, delivery failure, Vault audit failure, and explorer-delay exercises with sanitized evidence. |

## Highest-leverage next task

The next task is **existing-validator public identity and activation-readiness
reconciliation**, not another deposit:

1. Obtain the existing public-only deposit attestation or reconstruct only its
   public fields, then match its validator public key to the runtime signer.
2. Obtain the existing transaction receipt and DepositContract event through an
   approved public read provider or user-supplied public receipt. Do not enable
   Nethermind JSON-RPC, access Engine JWT, or touch wallet custody.
3. Fix T11's observer contract and tests before treating any duty query as
   operational evidence. A successful assignment is not a signed outcome.
4. Re-query private beacon validator state. Classify 404 as unresolved until
   the key and deposit event are correlated; then record deposit inclusion,
   queue state, activation epoch, and index.
5. Only after those gates and separate deployment approval, render/review a
   one-client fenced activation plan. Continue through first duty, UC-5
   post-recovery duty, then T18 restoration exercises.

In parallel, T5-T7 can finish their durability and rebuild proofs without
activating signing, but each live mutation still needs its own reviewed plan.
Any full zero-resource teardown and redeployment of the related validator,
signer, delivery, and supporting resources is last, after public-key/deposit
identity, observer correctness, activation state, and exact one-client fencing
all pass. It requires its own exact reviewed plan and authorization.

## Operational follow-up

The current private-EKS wrapper deletes its local session log and kills the
plugin process, but does not retain the server-side SSM session ID needed for
deterministic `terminate-session`. Sixteen read-only reconnaissance sessions were
opened and explicitly cleaned up by the evidence collector in this task; this
agent opened none. Add exact server-side ownership capture and cleanup to the
wrapper before the next multi-query live inspection.
