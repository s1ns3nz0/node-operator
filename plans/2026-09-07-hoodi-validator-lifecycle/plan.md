# Hoodi validator lifecycle

The target is one newly generated Hoodi validator and complete non-secret
evidence from custody through its first observed duties. The earlier
`test-*` ceremony is intentionally excluded.

## Use cases

1. **UC-1 — custody and deposit preflight.** A fresh EIP-2335 key is created
   outside the repository. The operator obtains a public-only deposit
   attestation containing the validator public key, Hoodi network, exact 32
   HoodiETH amount, and chosen withdrawal address. The human submits the
   wallet transaction; the software does not possess a wallet credential.
2. **UC-2 — hardened signer onboarding.** The encrypted keystore and password
   are transferred through a short-lived, scoped Vault ceremony. A persistent,
   authenticated slashing database and TLS-authenticated signer start with the
   expected public key only.
3. **UC-3 — deposit and activation observation.** A read-only watcher records
   beacon/execution sync, deposit visibility, activation-queue state, and the
   resulting validator index without recording secrets.
4. **UC-4 — validator duties and fencing.** Prysm validator client starts only
   after UC-2 and UC-3 gates. It talks solely to the in-cluster beacon API and
   signer. Evidence records readiness and duty/attestation outcomes; a second
   signer path is prevented by one active lease plus slashing protection.
5. **UC-5 — safe interruption and recovery.** Revoking workload access or
   removing the active lease fails closed. A reviewed recovery ceremony can
   restore the scoped access and records the recovery without exposing any
   secret.

## Implementation tasks

1. **T1 — log and evidence schema.** Define a versioned envelope with a
   correlation ID, public validator key, deposit-data hash, transaction hash,
   Vault request ID, Kubernetes object UID, and release SHA. Reject secrets.
2. **T2 — immutable audit archive.** Create a new `validator-audit` S3 bucket
   with SSE-KMS, versioning, TLS-only access, EventBridge, and two-year
   governance Object Lock. The existing bucket cannot be retrofitted with
   Object Lock.
3. **T3 — private delivery identity.** Add only the VPC endpoints and Pod
   Identity permissions required by log collectors to reach CloudWatch Logs,
   S3, and STS.
4. **T4 — Kubernetes log collection.** Deploy Fluent Bit with structured
   Kubernetes metadata for validator-related workloads, node logs, and
   Kubernetes events.
5. **T5 — Vault audit durability.** Add two non-raw audit devices, a dedicated
   encrypted audit volume per Vault pod, forwarding, health alerts, and request
   ID deduplication.
6. **T6 — hot and archive delivery.** Retain normal workload logs in
   CloudWatch for 90 days and security/Vault logs for 365 days; archive all
   accepted records in S3 and emit daily integrity manifests.
7. **T7 — derived search index.** Index only allowlisted metadata in
   OpenSearch; prove it can be rebuilt solely from S3.
8. **T8 — internal chain observer.** Collect private Prysm beacon sync, deposit
   observation, activation state, validator index, and duty status.
9. **T9 — external execution observer.** Confirm the human-submitted Hoodi
   deposit transaction and event via Etherscan without using explorer output as
   an operational source of truth.
10. **T10 — external consensus observer.** Confirm validator status and duty
    activity by public key through Beaconcha.in, recording URL, timestamp and
    response hash only.
11. **T11 — disagreement handling.** Alert on disagreement between internal
    and external sources and distinguish explorer delay/failure from node
    failure.
12. **T12 — UC-1.** Fresh-key ceremony, deposit attestation, human signing
    gate, and Etherscan transaction evidence.
13. **T13 — UC-2.** Scoped Vault onboarding, persistent authenticated slashing
    database, signer transport boundary, and audit evidence.
14. **T14 — UC-3.** Deposit-to-activation timeline and independently observed
    validator index.
15. **T15 — UC-4.** Validator client duties, signer correlation, fence lease,
    and external duty confirmation.
16. **T16 — UC-5.** Revoke/fence/recovery procedure with slashing continuity
    and first post-recovery duty evidence.
17. **T17 — restoration and failure tests.** Reindex, archive recovery,
    delivery failure, Vault audit failure, and explorer delay tests.

## Evidence authority

Private Prysm and signed custody records are operational sources of truth.
Hoodi Etherscan verifies the deposit transaction; Beaconcha.in verifies public
validator status and duties. Both explorers are independent corroboration only:
their failure can raise an alert but cannot start, stop, or authorize signing.

The human wallet signature, the activation queue, and the first real duty are
external gates, never automated deployment steps.
