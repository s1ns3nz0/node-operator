# Foundation existing-network mode: bounded implementation

Approved design boundary: Sol integration owner, 2026-09-08. This is part of
requirement 5, not a replacement for fresh deployment or the original goal.

- Owner: Terra `/root/security_goal_dast`, isolated new source worktree.
- Files: `infra/foundation-network/`, focused foundation tests and operations
  documentation only. Do not alter frozen source PR127, other worktrees or
  baseline resource definitions.
- Preserve the fresh-deployment default and its current network outputs.
- Existing mode reads baseline VPC/private subnets/private route table via data
  sources and verifies their VPC/CIDR relationships. It owns exactly the six
  inventory-backed NAT/public components listed in network-ownership-review.md.
- No managed VPC, private subnet/table/route/association in existing mode; no
  reassociation of workloads and no duplicate state ownership.
- Explicit validated inputs and ownership-specific outputs; no account-specific
  live IDs baked into module defaults, no blanket ignore_changes or scanner waiver.
- Rendered Terraform plans must assert exact managed address/count boundaries
  for both modes, mode input failures and unchanged fresh-deployment behavior.
- Validation: fmt, validate/rendered plans, relevant release contracts, diff
  check, independent Sol review. Keep raw plans/state private.
- Escalate ambiguity in ownership or routing, new scope, network replacement,
  test gaps or inability to preserve default contract. Do not silently omit it.
- No import, state migration, apply, deployment, publishing or merge authorized
  by this subtask. A later exact imported-state preview and independent approval
  are required before any live change.
- Requested tier: Terra. Record any model fallback explicitly.

Evidence starts as implementation pending. Success of this code task alone
does not complete requirement 5; actual state ownership and no-drift/access
proof remain separate completion gates.
