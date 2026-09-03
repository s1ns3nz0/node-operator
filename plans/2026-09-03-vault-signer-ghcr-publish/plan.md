# Vault signer GHCR publication

1. Add the digest-verified Vault signer Dockerfile to the existing content-addressed toolchain release matrix.
2. Push the reviewed commit and dispatch the repository-owned release workflow.
3. Confirm the job outcome and the published GHCR manifest digest.
4. Record non-sensitive evidence and obtain a clean-room debrief.

Only the GHCR image publication and workflow dispatch are authorized. Terraform, AWS, Vault, EKS, and secret changes remain out of scope.
