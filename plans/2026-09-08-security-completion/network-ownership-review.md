# Existing network ownership review

Observed 2026-09-08 using read-only EC2 APIs and baseline state version
`O8sX4lE1_UE4LcE6MIuDK0llRo4yVbAY`. Raw state remains private and is not included.
This inventory is not authorization to import, move, replace or apply resources.

## Confirmed ownership

| Live component | Existing owner | Reconciliation constraint |
| --- | --- | --- |
| VPC `vpc-085bf2e5a43f0de37` | baseline `aws_vpc.private` | Never duplicate in foundation state |
| Private subnets `subnet-06a7598310d4d51d6`, `subnet-04d9d7ea60d4999ac` | baseline `aws_subnet.private[0/1]` | Preserve CIDRs and workload placement |
| Private route table `rtb-0e82fb15326883352` | baseline `aws_route_table.private` | Preserve default NAT and S3 endpoint routes |
| Private route associations `rtbassoc-05a314b14b19d465c`, `rtbassoc-073d91233af252a54` | baseline `aws_route_table_association.private[0/1]` | Do not associate subnets from a second root |
| Interface endpoints and S3 endpoint | baseline | Retain owner; no recreation |

## Components absent from inspected baseline managed state

Absence from this state is not proof that no other operator owns them. Complete
the local/remote state inventory and explicit address/ID review before import.

A bounded search of `*.tfstate` under `/private/tmp` and the user's
`node-operator` workspace found only the inspected baseline copy referencing
these IDs, with no managed resources for the six components. The current
`node-operator/` prefix in the known state bucket contains baseline, bootstrap
and the isolated backend canary only. This does not inventory unrelated
directories, other buckets, external operators or nonstandard state files.

| Component | Observed ID | Configuration |
| --- | --- | --- |
| NAT public subnet | `subnet-0a132b51cd663eeaa` | `10.80.32.0/28`, `ap-northeast-2a`, public-IP autoassign false |
| NAT gateway | `nat-02d4eabc0b940f8d4` | available, public, above subnet |
| NAT EIP allocation | `eipalloc-0ae83bf5a52ce9364` | attached to above NAT |
| Internet gateway | `igw-0d5c4a38f3238bf7c` | target of public default route |
| Public route table | `rtb-0d44b65f6b8fd3095` | default route to above IGW |
| Public route association | `rtbassoc-052bdd657504684b9` | above NAT subnet/public table |

The VPC main route table `rtb-02dcb622574eb73e4` has only its local route and no
explicit subnet association. Do not adopt or modify this default table merely
because it appears in the inventory.

## Proposed implementation boundary

The existing `infra/foundation-network` module creates a new VPC, a distinct
Hoodi subnet and different NAT CIDR. Applying it unchanged is not a safe
reconciliation of the live network. Keep that fresh-deployment behavior intact.

A separately reviewed existing-network mode can reference the baseline-owned
VPC/subnets/route table through data sources and own only positively verified
unowned NAT/public components. It must not manage the baseline's private route
or subnet associations. The resulting ownership split must be explicit in
outputs, documentation and state inventory. Do not call this the zero-resource
rebuild test or claim every foundation resource moved out of baseline.

The private route table's NAT default route also requires an explicit
single-owner decision in baseline. Do not introduce a standalone route resource
that conflicts with a table's inline route management, or leave the ownership
ambiguity unreported merely because the observed traffic path works.

Required before implementation/apply:

1. Verify other relevant local state files and remote state keys for all six IDs.
2. Review exact mode contract and import addresses; retain new-deployment tests.
3. Prepare private imported-state preview, independently review every planned
   action and require zero replacement/deletion and no routing change.
4. Only apply approved changes; verify exact owner, routes, endpoint access and
   full scoped no-drift plan. Migrate to its own encrypted remote key using the
   reviewed backup/content/metadata procedure, never force-copy.

Foundation requirement remains incomplete. The original all-five goal is not
reduced to this inventory or a compatible module configuration.
