# Relay registry verification repair

1. Inspect failed run34308784601 and canonical publisher policy.
2. Add only the missing repository download action and a scoped regression test.
3. Run contract checks, negative fixtures and independent Terra review.
4. Submit the repair for review; apply only a reviewed exact-resource IaC plan.
5. Verify allowed relay download and denied unrelated repository access before
   resuming publication verification. Do not deploy the incomplete candidate.

Separate prerequisite now verified: user reported operator AWS configuration
success; root executed a fresh operator login, root-ceremony status read and
self-revocation wrapper successfully against live Vault. No root ceremony began.
