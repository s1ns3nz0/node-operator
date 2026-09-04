# Live execution: zero-cost Vault internal TLS

1. Push the reviewed commit with `GITHUB_TOKEN` removed so the existing
   keyring GitHub credential is used. Confirm the exact remote branch head.
2. Generate a refresh-backed Terraform saved plan. Permit only the two
   cert-manager ECR repositories, their lifecycle policies, and required
   extension of the already-scoped mirror role. Review before apply.
3. Apply the exact saved plan. Dispatch one signed chart mirror and four
   allowlisted OCI image mirrors. Poll each until completion and verify only
   workflow/ECR non-sensitive digests.
4. Connect through the private SSM EKS path. Install the private cert-manager
   chart, wait for controller/webhook/cainjector readiness, then apply the
   Vault-only CA Certificate, leaf Certificate, and ingress policy.
5. Verify Certificate readiness and `vault-tls` existence/key names only.
   Do not print Secret data. Complete harness checks and independent debrief.

Stop immediately on an unexpected Terraform action, non-private reference,
mirror digest mismatch, public-network requirement, permission escalation, or
any command that could expose Secret content.
