# Private baseline live-plan review

1. Confirm the baseline-only input flags and the approved Terraform-role identity.
2. Generate a temporary saved plan against the initialized state with locking disabled.
3. Review resource action counts, private-network invariants, EKS/node capacity, interface endpoints, audit/log/KMS resources, and excluded signer/ECR resources.
4. Record the non-sensitive plan summary and obtain a clean-room debrief.

This is plan review only. The next baseline apply requires a separate, exact-plan approval.
