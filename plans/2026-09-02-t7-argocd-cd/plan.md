# T-7 Argo CD CD boundary

1. Keep Terraform limited to VPC, EKS, node group, addons, IAM, and endpoints.
2. Install Argo CD only after the approved Terraform apply and cluster access check.
3. Register workloads through a reviewed Argo CD `Application` manifest sourced from Git.
4. Require Synced + Healthy status before recording deployment evidence.
5. Keep repository credentials, tokens, and production destinations outside Git.
