# Private GitOps CD runner

1. Declare a dedicated GitOps CodeBuild runner, scoped role, VPC boundary, webhook, and namespace-scoped EKS view access.
2. Validate the enabled Terraform plan against the existing CodeConnections identity and private subnets.
3. Merge and apply only the reviewed runner resources through the Terraform apply role.
4. Run digest-bound CD verification, then implement and run the bounded disposable DAST step.
