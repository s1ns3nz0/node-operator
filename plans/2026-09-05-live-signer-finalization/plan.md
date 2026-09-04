# Live signer finalization

1. Validate the existing KMS-encrypted immutable ECR repository and least-privilege OIDC role.
2. Add retention for digest-derived signer tags and apply only that isolated resource.
3. Temporarily remove the environment-review mechanical blocker under the user's delegation, set required variables, dispatch the digest-only workflow, and verify the resulting ECR digest.
4. Restore the environment review protection and record non-sensitive evidence.
