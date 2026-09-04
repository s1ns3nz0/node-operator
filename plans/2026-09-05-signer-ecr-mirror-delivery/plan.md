# Signer ECR mirror delivery plan

1. Add a manual, protected-environment workflow that accepts only the approved
   GHCR signer repository at a sha256 digest.
2. Use GitHub OIDC to assume only the conditional Terraform-provisioned mirror
   role and copy to the one ECR repository.
3. Add a structural test that rejects tags, other sources, broad permissions,
   and mutable destinations.
4. Run local validation; publication remains a separately approved operation.
