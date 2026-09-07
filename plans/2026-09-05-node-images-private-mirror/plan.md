# Private node image mirror

1. Add a dedicated immutable, scan-on-push private ECR destination for node images.
2. Permit only the two reviewed source digests through the OIDC mirror allowlist.
3. Update hardened manifests to reference only the same-account private ECR digests.
4. Apply the isolated ECR foundation and dispatch both mirrors; verify ECR digests.
