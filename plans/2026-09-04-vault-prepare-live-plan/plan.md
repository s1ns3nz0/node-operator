# Live Vault bootstrap prepare-plan review

1. Re-read the verified private ECR artifact digests and non-secret private subnet IDs.
2. Generate a refresh-backed Terraform plan with the runner enabled and cluster-admin disabled.
3. Reject the plan unless it contains the runner prerequisites, omits the EKS cluster-admin association, and introduces no public network resources.
4. Record a non-sensitive summary and obtain an independent clean-room debrief. This task ends without apply.
