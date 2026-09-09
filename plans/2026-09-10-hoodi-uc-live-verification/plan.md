# Hoodi live UC verification

1. Revalidate the existing deposit and current validator identity (UC-1).
2. Capture fresh private Beacon state and assigned duties (UC-3/UC-4).
3. Recheck post-fence-recovery attestations through canonical inclusion and finality.
4. Correlate bounded Vault/signer audit metadata to a verified duty (UC-2).
5. Run the reviewed, fail-closed role-revocation exercise only after the normal-duty record is fixed; restore and prove a subsequent duty (UC-5).

Each UC remains independently PASS, FAIL, or PENDING; completion of one never implies another.
