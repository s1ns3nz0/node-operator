# Reviewed cross-pool connectivity reconciliation

Observed node placements and EC2 rules:

- System pool SG `sg-0ec5983137b84e841`: health proxies, signer and Vault-2.
- Hoodi pool SG `sg-00202a93030b8e4b2`: Prysm, Nethermind and Vault-0/1.
- Existing VPC egress and cross-pool TCP 8200 rules are present; cross-pool TCP
  3500, 30303 and 8201 ingress is absent. Vault-1 is active; Vault-2 is standby.
- Existing Kubernetes policy unions already permit the intended DAST and Vault
  HA flows. The hypothesis that DAST introduced first-policy isolation was
  disproven; do not remove those policies to fix the security-group layer.

Sol reviewed the following preparation boundary. Owner is
`/root/security_goal_ci_fallback` in a new isolated source worktree; root owns
signer proxy changes elsewhere. Do not modify frozen PR127 or revert others.

Exactly four new standalone SG-reference ingress rules:

1. System SG to Hoodi SG TCP 3500: fixed Prysm health endpoint.
2. System SG to Hoodi SG TCP 30303: fixed no-payload P2P proxy.
3. System SG to Hoodi SG TCP 8201: Vault HA.
4. Hoodi SG to System SG TCP 8201: Vault HA after leadership changes.

No CIDR ingress, public exposure, UDP, port range, general cross-pool allow,
egress change, credential access or NetworkPolicy relaxation. Verify actual
Pod ENI group inheritance/no separate SGP and absence of duplicate live rules
before planning. Maintain dedicated rendered assertions for all four rules.

Code and private saved-plan preparation are authorized; **apply is not yet**.
The exact targeted plan must have four creates and zero other updates,
deletes or replacements, including dependency expansion. Raw plans/state remain
outside Git with private permissions. Do not full-apply the legacy baseline or
adopt/remove old resources as a side effect. Root independently reviews the
saved plan, state identity and code before any later approved live operation.

After a later approved apply, require exact SG readback, original target health
checks and scoped Terraform no-drift evidence. Do not count permitted paths as
proof that the applications actually respond successfully.
