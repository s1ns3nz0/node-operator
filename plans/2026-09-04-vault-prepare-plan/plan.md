# Vault bootstrap prepare-plan review

1. Confirm the repaired CI gates and the current Vault bootstrap contract.
2. Produce a refresh-backed Terraform plan using the existing backend and explicit, non-secret live inputs.
3. Reject the result unless it creates the private executor prerequisites and omits `AmazonEKSClusterAdminPolicy`.
4. Record a non-sensitive summary, run local structural validation, and obtain a clean-room review.

This task ends at plan review. A separately approved apply is required before any infrastructure changes.
