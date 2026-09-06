# Legacy SSM state migration plan

The current baseline Terraform state contains two generations of operations
access addresses: legacy `temporary_ssm_ops_host` resources and transitional
`ssm_ops_host` data addresses. Operations access must move to an isolated
`ops-access` root and state before either generation is removed from the
baseline configuration. The state listing alone is not evidence that every
address still has a corresponding live AWS resource; refresh-backed planning
in the maintenance window is required.

1. Create the new root with a distinct encrypted state key and no dependency on
   workload, Vault, or GitOps resources except read-only EKS/VPC outputs.
2. Plan it with operations access disabled. Confirm it creates no host,
   scheduler, IAM role, endpoint, or security-group rule.
3. In a reviewed maintenance window, create the isolated host resources in the
   new state using Terraform import or a state move procedure that preserves
   each exact AWS identifier. Never recreate an active tunnel host implicitly.
4. Verify new-state ownership with `terraform state list`; retain only resource
   addresses and no raw state output in evidence.
5. Remove both legacy and transitional addresses from the baseline state only
   after the isolated state plans no replacement or destroy. Then remove their
   baseline configuration.
6. Test `ops-access apply`, private EKS tunnel, scheduled expiry update, and
   `ops-access destroy` independently. The execution identity needs the narrow
   Scheduler update permission required for the expiry schedule.

Do not combine this migration with a client, Vault, validator, or generic
baseline Terraform apply.
