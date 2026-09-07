# GitOps publisher attestation read-back

1. Add the minimal ECR read action on the existing single chart repository.
2. Validate the Terraform configuration and targeted plan.
3. Merge the reviewed infrastructure declaration and apply it.
4. Re-run the GitOps publish workflow to prove sign, attest, and verify.
