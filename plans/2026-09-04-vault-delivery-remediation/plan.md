# Vault delivery remediation plan

1. Pin the Vault bootstrap toolchain and approve its immutable release digest.
2. Bind runtime images and the Vault Helm archive to the reviewed OCI allowlist.
3. Mirror the approved artifacts to private ECR and verify source/destination integrity.
4. Repair only the ECR/IAM prerequisites surfaced by the mirror jobs.
5. Preserve offline prepare/revoke contract checks; do not deploy or initialize Vault.
6. Run the clean-room debrief and retain non-sensitive evidence.

Status: steps 1–4 complete; step 5 remains the next operational gate.
