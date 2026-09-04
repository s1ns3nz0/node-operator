# Vault bootstrap toolchain activation

1. Confirm the main toolchain release produced the digest-pinned Vault bootstrap image.
2. Add only that digest to the reviewed GitOps OCI allowlist.
3. Merge the allowlist, dispatch the protected OIDC mirror, and verify the private ECR digest.
4. Update the dedicated CodeBuild project to consume the mirrored digest and verify its private execution path.
