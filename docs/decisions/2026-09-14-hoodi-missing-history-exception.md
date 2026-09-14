# Hoodi-only missing-history exception

- Status: accepted
- User approval: 2026-09-14 conversation; option 2, then simplified procedure approved.
- Product spec: `docs/product-specs/installer-e2e-duty.md`

Complete prior signing history is unavailable for the existing Hoodi identity.
Implement one explicit operator command which verifies stopped signing paths,
registers only the public key if necessary, runs the selected Web3Signer native
watermark repair against the bound retained slashing database, and verifies the
persisted floors. Preserve existing database records. Never describe synthetic
registration or repaired floors as recovered signing history or a guarantee
against slashing. Unknown prior signatures and another signer remain risks.

This is a testnet portfolio exception, not the default installer path. No mainnet,
new key, deposit, automatic activation, or bypass of readiness/custody/singleton
checks is authorized. The command must leave signing stopped on success or
failure. Subsequent activation uses the existing guarded procedure.

This coding task authorizes local implementation and isolated tests only, not
AWS access, production database modification, publication, merge, or activation.
