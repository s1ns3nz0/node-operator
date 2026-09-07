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

## Sequence

1. Implement release-contained runtime manifests, policy contracts, custody
   helpers, log collector, and UC orchestration scripts.
2. Validate all artifacts locally and render manifests without secrets.
3. Inspect the private EKS environment read-only; record whether node clients
   are synced and whether runtime prerequisites are available.
4. Run UC-1 through UC-2 with a newly created key. Pause before the wallet
   deposit until the human confirms the public deposit fields.
5. After human wallet submission, observe UC-3 until activation. Run UC-4 and
   UC-5 only after the validator is active.

The deposit confirmation and activation-queue wait are intentionally separate
human/network gates, not automatic deployment steps.
