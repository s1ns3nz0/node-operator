# Private GitOps foundation

1. Create immutable, scan-on-push ECR OCI repositories and retain only reviewed artifacts.
2. Bind a GitHub OIDC role to the exact `gitops-oci-mirror` Environment; grant destination-only ECR upload plus manifest-digest read.
3. Make the promoted live foundation the Terraform default while keeping isolated offline fixtures explicitly disabled.
4. Require a full source digest, use it as the immutable ECR tag, and verify ECR reports the same digest after a mirror.
5. Keep Vault out of the bootstrap path: the Environment has only non-secret account and role configuration.
6. Validate enabled offline planning, targeted live no-drift scope, and independent debrief before any artifact publication.
