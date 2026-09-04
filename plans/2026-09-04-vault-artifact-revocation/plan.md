# Vault artifact mirror and access revocation

1. Verify and pin the Vault chart archive and OCI runtime/toolchain inputs.
2. Add a dedicated chart mirror workflow that verifies the archive SHA-256 before pushing it to private ECR.
3. Separate temporary EKS access into prepare, deploy, and revoke Terraform inputs; make revocation verifiable.
4. Validate contracts and obtain independent review before any publish or apply.
