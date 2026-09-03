# T-2: Terraform security baseline

1. Define non-secret, offline Terraform inputs and private-network boundaries.
2. Implement isolated Terraform modules for approved EKS baseline resources.
3. Add static policy fixtures rejecting public endpoints, unencrypted volumes,
   broad IAM, and invalid node-group capacity.
4. Validate offline only; no provider authentication, plan, or apply.
5. Independently review and write a clean-room debrief.

T-1 is explicitly deferred because its external contract package does not yet
exist. This task must not introduce an evidence-export contract substitute.
