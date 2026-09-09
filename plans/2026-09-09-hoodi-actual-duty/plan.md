# Actual Hoodi duty

1. Read current private beacon, validator, signer, PVC and fence state.
2. Refresh public deposit proof, private validator status and TLS signer identity; use reviewed activation gates.
3. Activate only the existing singleton and fence if all gates pass; preserve rollback on failure.
4. Correlate assignment, signed submission and on-chain inclusion/finality. Assignment alone is not duty success.
5. Record public/non-sensitive evidence; leave restore rehearsal incomplete and Vault unchanged.
