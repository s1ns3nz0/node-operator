# Private Kyverno admission

1. Approve the exact Kyverno chart and controller image digests.
2. Mirror them to immutable private ECR and verify digest equality.
3. Install the chart from private ECR, verify webhook readiness, then dry-run and apply the scoped policy.
4. Record only non-sensitive admission outcomes.
