# Legacy SSM state migration plan

The current baseline Terraform state contains two generations of operations
access addresses: legacy `temporary_ssm_ops_host` resources and transitional
`ssm_ops_host` data addresses. Operations access must move to an isolated
`ops-access` root and state before either generation is removed from the
baseline configuration. The state listing alone is not evidence that every
address still has a corresponding live AWS resource; refresh-backed planning
in the maintenance window is required.

## Current ownership discovery (2026-09-08)

The running host `i-02c57d75e7f6810b1` is already owned by a separate **local**
ops state, not by the baseline's stale host address. The observed local state
has lineage `4194a7ca-cf28-4cce-2f92-84cb76ddbe60`, serial 10, and nine managed
resources. The stale baseline instance `i-0b1e225356d83549e` is no longer returned
by EC2. Do not recreate it or import the running host from that stale address.

For this existing ops state, preserve all resource/content identities while
migrating to the isolated encrypted remote key. Compare and record the original
and resulting lineage/serial: Terraform 1.5.7 can reset these metadata fields
when initializing an empty remote destination, as documented in
[bootstrap-state reconciliation](bootstrap-state-reconciliation.md). Never
force-rewrite metadata to hide a mismatch. Set
`existing_ssm_endpoint_security_group_id = "sg-01b10b4d88ad3f014"`,
`manage_existing_endpoint_ingress_rule = true`, and
`manage_cluster_ingress_rule = true`: this state already owns both ingress
rules. The module's moved blocks retain their old uncounted addresses as `[0]`.
These settings are not universal defaults for a host whose rules have another
owner. A migration plan must show no rule deletion/replacement and no host
replacement before the new state is made authoritative.

Back up the original state privately, verify that the destination key is empty,
and use the reviewed backend migration procedure; never force-copy or discard
the original state. Do not simultaneously leave two writable authoritative
copies. Monitoring and EBS-optimization changes are separate from ownership
migration. The current private preview with AWS provider 5.100 proposes host
replacement solely for `ebs_optimized: false -> true`; this blocks resource
apply. EC2 reports that this `t3.micro` type is EBS-optimized by default, so
the representation mismatch is not evidence that the actual capability is
missing. Do not replace or stop the host, disable hardening for new instances,
or add an exception without a reviewed decision. Any future host-changing plan
also requires checking active SSM/DAST sessions and explicit impact approval.

## General migration sequence

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
