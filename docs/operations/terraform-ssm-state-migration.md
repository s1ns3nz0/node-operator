# Legacy SSM state migration plan

The current baseline Terraform state contains two generations of operations
access addresses: legacy `temporary_ssm_ops_host` resources and transitional
`ssm_ops_host` data addresses. Operations access must move to an isolated
`ops-access` root and state before either generation is removed from the
baseline configuration. The state listing alone is not evidence that every
address still has a corresponding live AWS resource; refresh-backed planning
in the maintenance window is required.

1. Create the new root with a distinct encrypted state key and no dependency on
   workload, Vault, or GitOps resources except read-only EKS/VPC outputs. Copy
   `infra/ops-access/backend.hcl.example` outside the bundle and use the
   `node-operator/ops-access/terraform.tfstate` key; do not use local state.
2. Run the isolated `ops-access plan` command. It may propose a new host only
   for a genuinely zero-resource environment. Against an existing environment,
   it is evidence to review: do not apply a plan that replaces an active host,
   endpoint, IAM role, or security-group rule.
3. In a reviewed maintenance window, create the isolated host resources in the
   new state using Terraform import or a state move procedure that preserves
   each exact AWS identifier. Never recreate an active tunnel host implicitly.
   If the live host uses shared baseline SSM interface endpoints, set
   `existing_ssm_endpoint_security_group_id` and
   `manage_cluster_ingress_rule = false` in the non-secret migration tfvars.
   This root then owns the host and its egress only; it neither recreates nor
   takes ownership of the shared endpoints or the baseline-owned EKS ingress.
4. Verify new-state ownership with `terraform state list`; retain only resource
   addresses and no raw state output in evidence.
5. Remove both legacy and transitional addresses from the baseline state only
   after the isolated state plans no replacement or destroy. Then remove their
   baseline configuration.
6. Test `ops-access apply --allow-create`, private EKS tunnel, and
   `ops-access destroy --allow-create` independently in a disposable
   environment. There is deliberately no Scheduler implementation or
   permission in this root.

Do not combine this migration with a client, Vault, validator, or generic
baseline Terraform apply.
