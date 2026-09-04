# Private GitOps source and Vault boundary

1. Keep ECR OCI as the only Argo CD data plane source because the private VPC has no GitHub egress.
2. Define a future GitHub App mirror identity with read-only Contents permission; do not create it in this task.
3. Define the future Vault KV and Vault Secrets Operator contract without creating a Vault secret or Kubernetes Secret.
4. Add structural tests and record only non-sensitive evidence.
5. Do not create an Argo CD Application, repository credential, or Vault configuration in this task.
