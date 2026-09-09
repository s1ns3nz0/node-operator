# Complete operational UC evidence

1. Observe current Vault, validator, storage and audit metadata without secret exports; compare Vault candidate to live Helm configuration.
2. Resolve any parity and migration safety gaps, maintain fresh signed evidence and acquire a fresh snapshot through the user-only ceremony.
3. Review and deliver approved standby-first Vault changes, verify unseal/quorum/audit and isolated Agent/Injector canary.
4. Verify current Hoodi activation, exact single-client fencing, mTLS signer and retained slashing data before starting duties.
5. Collect and review UC-1..5 evidence including actual signed duty and post-recovery duty; fix gaps and repeat affected tests.
6. Publish/merge tested and reviewed changes using delegated authority, without impersonating review identities. Stop for missing private credentials rather than weaken gates.

Goal tool note: existing goal is blocked and create_goal rejected replacement as unfinished. This work proceeds under the user's explicit instruction; do not falsely mark the older goal complete merely to replace it.
